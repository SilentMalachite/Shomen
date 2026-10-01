require "uri"
require "./event"
require "./recorded"
require "./append_signal"
require "./store_adapter"
require "./sqlite_adapter"
require "./postgres_adapter"
require "./append_watcher"

# The append-only event log. The scheme of the URL picks the database
# (docs/decisions/20260929-phase6-store-adapters.md). After a commit an
# append wakes what waits for it in this process; the appends of other
# processes wake it through Shomen::AppendWatcher.
class Shomen::Store
  POLL_INTERVAL = 5.seconds

  @@signals = {} of String => Shomen::AppendSignal
  @@signals_lock = Mutex.new
  # One per database in a process (docs/decisions/20261001-phase7-append-watcher.md).
  @@watchers = {} of String => Shomen::AppendWatcher
  @@watchers_lock = Mutex.new

  @adapter : Shomen::StoreAdapter
  @signal : Shomen::AppendSignal
  # The watcher this store started; it stops it on close.
  @watcher : Shomen::AppendWatcher? = nil
  @closed = false

  # How often a watcher this store starts polls; a consumer on this store
  # tries again at least this often.
  getter poll_interval : Time::Span

  def initialize(url : String, @poll_interval : Time::Span = POLL_INTERVAL)
    raise ArgumentError.new("poll_interval must be positive") unless @poll_interval.positive?
    uri = begin
      URI.parse(url)
    rescue ex : URI::Error
      raise ArgumentError.new("store URL is not valid: #{ex.message}")
    end
    @adapter = case uri.scheme
               when "sqlite3"
                 Shomen::SQLiteAdapter.new(uri)
               when "postgres", "postgresql"
                 Shomen::PostgresAdapter.new(uri)
               else
                 raise ArgumentError.new("store URL must use sqlite3, postgres, or postgresql, got #{uri.scheme.inspect}")
               end
    key = @adapter.key
    @signal = @@signals_lock.synchronize { @@signals[key] ||= Shomen::AppendSignal.new }
  end

  def append(stream : String, expected_version : Int64, events : Array(Shomen::Event)) : Nil
    raise ArgumentError.new("stream must not be empty") if stream.empty?
    raise ArgumentError.new("expected_version must not be negative") if expected_version < 0
    return if events.empty?
    events.each do |event|
      raise ArgumentError.new("#{event.event_type} at must be UTC, got #{event.at}") unless event.at.utc?
    end
    rows = events.map { |event| {event.event_type, event.to_json, event.at.to_rfc3339} }
    @signal.announce(@adapter.append(stream, expected_version, rows))
  end

  # The highest id this process knows the database holds: its own appends
  # at once, those of other processes once a notification or a poll tells
  # it. 0 before the first.
  def last_appended : Int64
    @signal.last
  end

  # Waits until this process learns of an event with an id above after.
  # The first wait on a database starts listening and polling for it.
  # False when within passes first.
  def wait_for_append(after : Int64, within : Time::Span) : Bool
    watch
    @signal.wait(after, within)
  end

  def read(after : Int64, limit : Int32 = 500) : Array(Shomen::Recorded)
    @adapter.read(after, limit).map { |row| recorded(row) }
  end

  # Creates the row of the consumer called name, at checkpoint 0, with the
  # tables the block creates (docs/decisions/20261001-phase7-consumer-batch.md).
  def register(name : String, & : DB::Connection ->) : Nil
    raise ArgumentError.new("consumer name must not be empty") if name.empty?
    @adapter.register(name) { |connection| yield connection }
  end

  # The checkpoint any process committed last for the consumer called name.
  def checkpoint(name : String) : Int64
    @adapter.checkpoint(name)
  end

  # Lends a connection and returns what the block returns. On SQLite the
  # block must not call this store.
  def using_connection(& : DB::Connection -> T) : T forall T
    result = nil
    @adapter.using_connection { |connection| result = yield connection }
    result.as(T)
  end

  # One batch of the consumer called name
  # (docs/decisions/20261001-phase7-consumer-batch.md). An event that cannot
  # be decoded fails like one whose react or write raises.
  def consume(name : String, limit : Int32, react : Proc(Shomen::Recorded, Nil), write : Proc(Shomen::Recorded, DB::Connection, Nil)) : Int32
    @adapter.consume(
      name, limit,
      ->(row : Shomen::StoreAdapter::Stored) { react.call(recorded(row)) },
      ->(row : Shomen::StoreAdapter::Stored, connection : DB::Connection) { write.call(recorded(row), connection) },
    )
  end

  def close : Nil
    watcher = @@watchers_lock.synchronize do
      @closed = true
      owned = @watcher
      @watcher = nil
      @@watchers.delete(@adapter.key) if owned
      owned
    end
    watcher.try(&.stop)
    @adapter.close
  end

  private def recorded(row : Shomen::StoreAdapter::Stored) : Shomen::Recorded
    id, stream, version, type, payload = row
    Shomen::Recorded.new(id, stream, version, Shomen::Event.decode(type, payload))
  end

  private def watch : Nil
    @@watchers_lock.synchronize do
      return if @closed
      key = @adapter.key
      unless @@watchers.has_key?(key)
        watcher = Shomen::AppendWatcher.new(@adapter, @signal, @poll_interval)
        @@watchers[key] = watcher
        @watcher = watcher
      end
    end
  end
end
