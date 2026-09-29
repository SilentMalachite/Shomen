# Wakes the fibers of this process that wait for an append to one
# database file. Appends in other processes do not reach it (phase 7).
class Shomen::AppendSignal
  @last = 0_i64
  @waiters = [] of Channel(Nil)
  @lock = Mutex.new

  # The highest id announced, 0 before the first.
  def last : Int64
    @lock.synchronize { @last }
  end

  def waiting : Int32
    @lock.synchronize { @waiters.size }
  end

  def announce(id : Int64) : Nil
    @lock.synchronize do
      @last = id if id > @last
      @waiters.each do |waiter|
        select
        when waiter.send(nil)
        else
        end
      end
    end
  end

  # True as soon as an id above after is announced, false when within
  # passes first. The waiter leaves the list either way.
  def wait(after : Int64, within : Time::Span) : Bool
    waiter = Channel(Nil).new(1)
    @lock.synchronize do
      return true if @last > after
      @waiters << waiter
    end
    begin
      select
      when waiter.receive
        true
      when timeout(within)
        false
      end
    ensure
      @lock.synchronize { @waiters.delete(waiter) }
    end
  end
end
