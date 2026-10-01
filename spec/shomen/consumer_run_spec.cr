require "../spec_helper"

describe "a started Shomen::Consumer" do
  store_it "applies each append without being asked, until stop" do |store|
    notes = SpecConsumers::Notes.new(store)
    notes.start
    begin
      store.append("s", 0_i64, note("one"))
      notes.read(1_i64, within: 5.seconds) { |_| }
      store.append("s", 1_i64, note("two"))
      notes.read(2_i64, within: 5.seconds) { |_| }
      notes.texts.should eq(%w(one two))
    ensure
      notes.stop
    end
  end

  store_it "goes on to the next batch at once after a full one" do |store|
    count = Shomen::Consumer::BATCH + 1
    store.append("s", 0_i64, noted(Array.new(count) { |index| "n#{index}" }))
    notes = SpecConsumers::Notes.new(store)
    notes.start
    begin
      # The store polls every 5 seconds, so only a batch that follows at
      # once arrives within 2.
      notes.read(count.to_i64, within: 2.seconds) { |_| }
    ensure
      notes.stop
    end
  end

  store_it "retries a failing event with a growing delay, logs each failure, and does not skip it" do |store|
    notes = SpecConsumers::Notes.new(store)
    notes.fail_react = "one"
    notes.failures = 2
    store.append("s", 0_i64, noted(%w(one two)))
    Log.capture("shomen") do |logs|
      notes.start
      begin
        notes.read(2_i64, within: 5.seconds) { |_| }
      ensure
        notes.stop
      end
      logs.check(:warn, /\Aconsumer spec_notes failed on the event after 0; retrying in 10 ms\z/)
      logs.next(:warn, /\Aconsumer spec_notes failed on the event after 0; retrying in 20 ms\z/)
    end
    notes.texts.should eq(%w(one two))
  end

  store_it "keeps other consumers going while one fails" do |store|
    failing = SpecConsumers::Notes.new(store, "spec_failing")
    failing.fail_react = "one"
    other = SpecConsumers::Notes.new(store, "spec_other")
    store.append("s", 0_i64, note("one"))
    failing.start
    other.start
    begin
      other.read(1_i64, within: 5.seconds) { |_| }
      failing.checkpoint.should eq(0_i64)
    ensure
      failing.stop
      other.stop
    end
  end

  store_it "stops at once while it waits for an append" do |store|
    notes = SpecConsumers::Notes.new(store)
    notes.start
    store.append("s", 0_i64, note("one"))
    notes.read(1_i64, within: 5.seconds) { |_| }
    Log.capture("shomen") do |logs|
      notes.stop(within: 1.second)
      logs.empty
    end
  end

  it "rejects a retry_first that is not positive, and a retry_limit below it" do
    with_store do |store|
      expect_raises(ArgumentError, "retry_first must be positive") do
        SpecConsumers::Notes.new(store, retry_first: 0.seconds)
      end
      expect_raises(ArgumentError, "retry_limit must not be less than retry_first") do
        SpecConsumers::Notes.new(store, retry_first: 2.seconds, retry_limit: 1.second)
      end
    end
  end
end
