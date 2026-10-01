require "../spec_helper"

private def receive_within(channel : Channel(Bool)) : Bool
  select
  when value = channel.receive
    value
  when timeout(5.seconds)
    raise "no answer within 5 seconds"
  end
end

# Lets other fibers run until count of them wait on the signal.
private def until_waiting(signal : Shomen::AppendSignal, count : Int32) : Nil
  deadline = Time.instant + 5.seconds
  until signal.waiting == count
    raise "no fiber waited within 5 seconds" if Time.instant > deadline
    Fiber.yield
  end
end

describe Shomen::AppendSignal do
  it "wakes a fiber that waits for an id above the one it saw" do
    signal = Shomen::AppendSignal.new
    woke = Channel(Bool).new(1)
    spawn { woke.send(signal.wait(after: 0_i64, within: 5.seconds)) }
    until_waiting(signal, 1)
    signal.announce(3_i64)
    receive_within(woke).should be_true
    signal.last.should eq(3_i64)
    signal.waiting.should eq(0)
  end

  it "returns at once when a higher id came before the wait" do
    signal = Shomen::AppendSignal.new
    signal.announce(2_i64)
    signal.wait(after: 1_i64, within: 5.seconds).should be_true
    signal.waiting.should eq(0)
  end

  it "returns false after the limit and forgets the waiter" do
    signal = Shomen::AppendSignal.new
    signal.announce(2_i64)
    signal.wait(after: 2_i64, within: 1.millisecond).should be_false
    signal.waiting.should eq(0)
  end

  it "never lowers the last id" do
    signal = Shomen::AppendSignal.new
    signal.announce(5_i64)
    signal.announce(4_i64)
    signal.last.should eq(5_i64)
  end

  it "does not wake a waiter for an id at or below the one it waits past" do
    signal = Shomen::AppendSignal.new
    woke = Channel(Bool).new(1)
    spawn { woke.send(signal.wait(after: 5_i64, within: 5.seconds)) }
    until_waiting(signal, 1)
    signal.announce(3_i64)
    signal.announce(5_i64)
    signal.waiting.should eq(1)
    select
    when woke.receive
      fail "the waiter woke too early"
    else
    end
    signal.announce(6_i64)
    receive_within(woke).should be_true
  end
end
