require "log"
require "./store_adapter"
require "./append_signal"

# Tells this process of the appends of every process: it polls the
# highest id, at once and then at an interval, and, on a database that sends notifications,
# listens on a connection of its own. Both announce to the signal, so a
# lost notification only adds delay
# (docs/decisions/20261001-phase7-append-watcher.md).
class Shomen::AppendWatcher
  RETRY_FIRST = 100.milliseconds
  STOP_LIMIT  = 5.seconds
  STOP_RETRY  = 50.milliseconds

  Log = ::Log.for("shomen")

  @stop = Channel(Nil).new
  @listened = Channel(Nil).new(1)
  @stopped = Atomic(Bool).new(false)

  def initialize(@adapter : Shomen::StoreAdapter, @signal : Shomen::AppendSignal, @interval : Time::Span)
    spawn(name: "shomen poll") { poll }
    spawn(name: "shomen listen") { listen } if @adapter.notifies?
  end

  def stopped? : Bool
    @stopped.get
  end

  # The connection may still be opening when the first interrupt runs, so
  # the interrupt repeats until the listen ends. The poll fiber is not
  # awaited: a poll in flight against a closed adapter raises, and poll
  # returns quietly because stopped? is already true.
  def stop : Nil
    return if @stopped.swap(true)
    @stop.close
    return unless @adapter.notifies?
    deadline = Time.instant + STOP_LIMIT
    until Time.instant > deadline
      begin
        @adapter.interrupt_listen
      rescue ex
        Log.warn(exception: ex) { "could not close the connection that listens for appends" }
      end
      select
      when @listened.receive
        return
      when timeout(STOP_RETRY)
      end
    end
    Log.warn { "the connection that listens for appends did not close within #{STOP_LIMIT}" }
  end

  private def catch_up : Nil
    @signal.announce(@adapter.last_id)
  end

  private def poll : Nil
    loop do
      begin
        catch_up
      rescue ex
        return if stopped?
        Log.warn(exception: ex) { "could not poll for appends" }
      end
      select
      when @stop.receive?
        return
      when timeout(@interval)
      end
    end
  end

  # Reads the highest id before each connection, so what was appended
  # while none listened arrives at once; an append between that read and
  # the LISTEN arrives with the next poll.
  private def listen : Nil
    delay = RETRY_FIRST
    until stopped?
      began = Time.instant
      begin
        catch_up
        break if stopped?
        @adapter.listen(->(id : Int64) { @signal.announce(id) })
      rescue ex
        break if stopped?
        Log.warn(exception: ex) { "lost the connection that listens for appends; connecting again" }
      end
      delay = RETRY_FIRST if Time.instant - began > delay
      select
      when @stop.receive?
        break
      when timeout(delay)
      end
      delay = {delay * 2, @interval}.min
    end
  ensure
    @listened.send(nil)
  end
end
