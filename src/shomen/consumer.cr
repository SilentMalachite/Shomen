require "db"
require "log"
require "./store"
require "./recorded"
require "./unavailable"

# A projection kept in tables, or a reaction, run outside the request. It
# applies the events after its checkpoint in batches, and a batch commits
# its writes and the new checkpoint together, so every process may run the
# same consumer (docs/decisions/20261001-phase7-consumer-api.md).
abstract class Shomen::Consumer
  BATCH       = 100
  RETRY_FIRST = 1.second
  RETRY_LIMIT = 1.minute
  STOP_LIMIT  = 5.seconds

  # docs/decisions/20261001-phase7-consumer-read.md
  WAIT        = 2.seconds
  CHECK_FIRST = 10.milliseconds
  CHECK_LIMIT = 200.milliseconds

  Log = ::Log.for("shomen")

  @registered = false
  @register_lock = Mutex.new
  @started = Atomic(Bool).new(false)
  @stopping = Atomic(Bool).new(false)
  @stop = Channel(Nil).new
  # Closed when the loop ends, which wakes every receiver.
  @stopped = Channel(Nil).new

  def initialize(@store : Shomen::Store, @retry_first : Time::Span = RETRY_FIRST, @retry_limit : Time::Span = RETRY_LIMIT)
    raise ArgumentError.new("retry_first must be positive") unless @retry_first.positive?
    raise ArgumentError.new("retry_limit must not be less than retry_first") if @retry_limit < @retry_first
  end

  # Names the checkpoint. A projection whose tables change shape takes a
  # new name (docs/decisions/20260929-scale-projection-rebuild.md).
  abstract def name : String

  # Creates the consumer's tables, once, before its first batch or read.
  def create_tables(connection : DB::Connection) : Nil
  end

  # Writes the consumer's tables, in the transaction that moves its
  # checkpoint. It must not call the store, as the store may run it inside
  # its lock.
  def write(recorded : Shomen::Recorded, connection : DB::Connection) : Nil
  end

  # A side effect outside the database, such as mail. It runs at least
  # once per event, so it must tolerate a repeat.
  def react(recorded : Shomen::Recorded) : Nil
  end

  # The checkpoint any process committed last.
  def checkpoint : Int64
    register
    @store.checkpoint(name)
  end

  # One batch of up to BATCH events after the checkpoint. Returns how many
  # it committed: 0 when there were none, or when another process holds or
  # moved the checkpoint. When an event fails, the events before it commit
  # and the error is raised.
  def run_once : Int32
    register
    @store.consume(
      name, BATCH,
      ->(recorded : Shomen::Recorded) { react(recorded) },
      ->(recorded : Shomen::Recorded, connection : DB::Connection) { write(recorded, connection) },
    )
  end

  # Yields a connection once the checkpoint reached id, and returns what
  # the block returns. Raises Shomen::Unavailable, rather than show an older
  # state, when within passes first. Registers first, so the consumer's
  # tables exist even for id 0, which neither waits nor reads the
  # checkpoint. The block must not call the store, as the store may run it
  # inside its lock.
  def read(id : Int64 = 0_i64, within : Time::Span = WAIT, & : DB::Connection -> T) : T forall T
    register
    await(id, within)
    @store.using_connection { |connection| yield connection }
  end

  # Runs batches in a fiber of its own until stop.
  def start : Nil
    return if @started.swap(true)
    spawn(name: "shomen consumer #{name}") { run }
  end

  # Tells the loop to stop and waits, up to within, for the batch in
  # progress to end. A loop that waits for an append or a retry stops at
  # once.
  def stop(within : Time::Span = STOP_LIMIT) : Nil
    return unless @started.get
    return if @stopping.swap(true)
    @stop.close
    select
    when @stopped.receive?
    when timeout(within)
      Log.warn { "consumer #{name} did not stop within #{within}" }
    end
  end

  private def register : Nil
    @register_lock.synchronize do
      return if @registered
      @store.register(name) { |connection| create_tables(connection) }
      @registered = true
    end
  end

  # Reads the checkpoint again after CHECK_FIRST, then twice as long each
  # time, at most CHECK_LIMIT, as the consumer may run in another process.
  private def await(id : Int64, within : Time::Span) : Nil
    return if id <= 0
    deadline = Time.instant + within
    check = CHECK_FIRST
    until checkpoint >= id
      left = deadline - Time.instant
      raise Shomen::Unavailable.new("#{name} did not reach event #{id} within #{within}") unless left.positive?
      sleep({check, left}.min)
      check = {check * 2, CHECK_LIMIT}.min
    end
  end

  # After a full batch the next runs at once; after any other, the loop
  # waits for an append after the last id it knew before that batch, or for
  # the store's poll interval, so it picks up a batch another process left
  # when it died.
  private def run : Nil
    delay = @retry_first
    until @stopping.get
      seen = @store.last_appended
      applied = 0
      begin
        applied = run_once
      rescue ex
        after = (@store.checkpoint(name) rescue nil)
        Log.warn(exception: ex) { "consumer #{name} failed on the event after #{after || "its checkpoint"}; retrying in #{delay.total_milliseconds.to_i} ms" }
        break if stopped_within?(delay)
        delay = {delay * 2, @retry_limit}.min
        next
      end
      delay = @retry_first
      next if applied == BATCH
      break if idle(seen)
    end
  ensure
    @stopped.close
  end

  # Waits for an append after seen, at most the store's poll interval. The
  # wait runs in a fiber of its own so stop ends this one at once; that
  # fiber ends by itself within the interval. True when stopped.
  private def idle(seen : Int64) : Bool
    woke = Channel(Nil).new(1)
    store = @store
    spawn(name: "shomen consumer wait") do
      store.wait_for_append(after: seen, within: store.poll_interval)
      woke.send(nil)
    end
    select
    when woke.receive
      false
    when @stop.receive?
      true
    end
  end

  private def stopped_within?(span : Time::Span) : Bool
    select
    when @stop.receive?
      true
    when timeout(span)
      false
    end
  end
end
