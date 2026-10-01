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
  REAP_RETRY  = 1.second

  Log = ::Log.for("shomen")

  @stop = Channel(Nil).new
  # Closed when each fiber ends, which wakes every receiver.
  @polled = Channel(Nil).new
  @listened = Channel(Nil).new
  @stopped = Atomic(Bool).new(false)

  def initialize(@adapter : Shomen::StoreAdapter, @signal : Shomen::AppendSignal, @interval : Time::Span, @stop_limit : Time::Span = STOP_LIMIT)
    spawn(name: "shomen poll") { poll }
    spawn(name: "shomen listen") { listen } if @adapter.notifies?
  end

  def stopped? : Bool
    @stopped.get
  end

  # Waits, up to stop_limit, for both fibers to end, so the store can close
  # the adapter without a fiber opening a connection on it again. The
  # interrupts run in a fiber of their own: a stuck one cannot hold stop
  # past the limit, and they go on after stop returns until the listen
  # ends, so a connection that opens late is closed as well.
  def stop : Nil
    return if @stopped.swap(true)
    @stop.close
    spawn(name: "shomen interrupt listen") { interrupt_until_listened } if @adapter.notifies?
    deadline = Time.instant + @stop_limit
    ended = ended_by?(@polled, deadline)
    ended = ended_by?(@listened, deadline) && ended if @adapter.notifies?
    Log.warn { "the watcher for appends did not stop within #{@stop_limit}" } unless ended
  end

  # The wait before this reconnect and the one after it: back to
  # RETRY_FIRST after a connection that lasted longer than the wait,
  # otherwise the wait, then twice it, at most interval.
  def self.backoff(wait : Time::Span, lasted : Time::Span, interval : Time::Span) : {Time::Span, Time::Span}
    wait = RETRY_FIRST if lasted > wait
    {wait, {wait * 2, interval}.min}
  end

  private def ended_by?(channel : Channel(Nil), deadline : Time::Instant) : Bool
    select
    when channel.receive?
      true
    when timeout({deadline - Time.instant, Time::Span.zero}.max)
      false
    end
  end

  # Warns of the first failure only, as the interrupts may go on for long.
  private def interrupt_until_listened : Nil
    retry = STOP_RETRY
    warned = false
    loop do
      select
      when @listened.receive?
        return
      else
      end
      begin
        @adapter.interrupt_listen
      rescue ex
        Log.warn(exception: ex) { "could not close the connection that listens for appends" } unless warned
        warned = true
      end
      select
      when @listened.receive?
        return
      when timeout(retry)
      end
      retry = {retry * 2, REAP_RETRY}.min
    end
  end

  private def catch_up : Nil
    @signal.announce(@adapter.last_id)
  end

  private def poll : Nil
    until stopped?
      begin
        catch_up
      rescue ex
        Log.warn(exception: ex) { "could not poll for appends" } unless stopped?
      end
      select
      when @stop.receive?
        break
      when timeout(@interval)
      end
    end
  ensure
    @polled.close
  end

  # Reads the highest id before each connection, so what was appended
  # while none listened arrives at once; an append between that read and
  # the LISTEN arrives with the next poll.
  private def listen : Nil
    wait = RETRY_FIRST
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
      wait, after = Shomen::AppendWatcher.backoff(wait, Time.instant - began, @interval)
      select
      when @stop.receive?
        break
      when timeout(wait)
      end
      wait = after
    end
  ensure
    @listened.close
  end
end
