# The connections of one server, each known by the fiber that serves it,
# so a shutdown can close the idle ones and the streams, and wait for the
# requests in progress (docs/decisions/20260929-phase6-shutdown.md).
class Shomen::Connections
  enum State
    Idle
    Busy
    Streaming
  end

  private class Entry
    getter io : IO
    property state = State::Idle

    def initialize(@io : IO)
    end
  end

  @entries = {} of Fiber => Entry
  @lock = Mutex.new
  @draining = false
  @waiters = [] of Channel(Nil)

  def open(io : IO) : Nil
    @lock.synchronize { @entries[Fiber.current] = Entry.new(io) }
  end

  def leave : Nil
    @lock.synchronize do
      @entries.delete(Fiber.current)
      announce_if_done
    end
  end

  # Marks the current connection busy while the block runs. A fiber that
  # serves no known connection, such as a spec that calls the handler,
  # just runs it.
  def request(& : ->) : Nil
    change(State::Busy)
    begin
      yield
    ensure
      change(State::Idle)
    end
  end

  # The request on the current connection became an SSE stream. A shutdown
  # does not wait for it and cuts it, at once when one already began.
  def stream : Nil
    io = @lock.synchronize do
      entry = @entries[Fiber.current]?
      next nil unless entry
      entry.state = State::Streaming
      announce_if_done
      entry.io if @draining
    end
    cut(io) if io
  end

  def draining? : Bool
    @lock.synchronize { @draining }
  end

  # The number of requests in progress.
  def busy : Int32
    @lock.synchronize { busy_count }
  end

  # Closes every idle connection and cuts every stream. From now on each
  # response says Connection: close.
  def drain : Nil
    entries = @lock.synchronize do
      @draining = true
      @entries.values.reject(&.state.busy?)
    end
    entries.each { |entry| entry.state.streaming? ? cut(entry.io) : close(entry.io) }
  end

  # True as soon as no request is in progress, false when within passes
  # first. It counts again before it returns: a request can begin after
  # drain, so one wake-up does not end the wait.
  def wait(within : Time::Span) : Bool
    deadline = Time.instant + within
    loop do
      waiter = Channel(Nil).new(1)
      @lock.synchronize do
        return true if busy_count == 0
        @waiters << waiter
      end
      begin
        select
        when waiter.receive
        when timeout(deadline - Time.instant)
          return @lock.synchronize { busy_count == 0 }
        end
      ensure
        @lock.synchronize { @waiters.delete(waiter) }
      end
    end
  end

  private def change(state : State) : Nil
    @lock.synchronize do
      if entry = @entries[Fiber.current]?
        entry.state = state
        announce_if_done
      end
    end
  end

  # Called with the lock held.
  private def busy_count : Int32
    @entries.count { |_, entry| entry.state.busy? }
  end

  # Called with the lock held. Wakes every wait each time no request is in
  # progress; a wait counts again for itself.
  private def announce_if_done : Nil
    return if busy_count > 0
    @waiters.each do |waiter|
      select
      when waiter.send(nil)
      else
      end
    end
  end

  # The client may have closed its side already.
  private def close(io : IO) : Nil
    io.close
  rescue IO::Error
  end

  # A stream may be stuck in a write to a client that stopped reading, and
  # close would flush the socket's buffer first and get stuck with it.
  # Shutting the socket down fails that write instead, and the fiber that
  # serves the stream closes the socket as it ends.
  private def cut(io : IO) : Nil
    return close(io) unless io.is_a?(Socket)
    begin
      io.close_write
    rescue IO::Error
    end
    begin
      io.close_read
    rescue IO::Error
    end
  end
end
