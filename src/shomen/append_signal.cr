# Wakes the fibers of this process that wait for an append to one
# database file. Whoever learns of an append announces its id; a waiter
# wakes only for an id above the one it waits past.
class Shomen::AppendSignal
  @last = 0_i64
  # Each waiter with the id it waits past.
  @waiters = [] of {Int64, Channel(Nil)}
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
      @waiters.each do |after, waiter|
        next unless after < id
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
      @waiters << {after, waiter}
    end
    begin
      select
      when waiter.receive
        true
      when timeout(within)
        false
      end
    ensure
      @lock.synchronize { @waiters.delete({after, waiter}) }
    end
  end
end
