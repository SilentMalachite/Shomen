require "../spec_helper"

describe Shomen::Projection do
  it "applies every event from id 1 and records the checkpoint" do
    with_store do |store|
      store.append("a", 0_i64, note("one"))
      store.append("b", 0_i64, note("two"))
      log = SpecEvents::Log.new(store).catch_up
      log.lines.map(&.text).should eq(%w(one two))
      log.checkpoint.should eq(2_i64)
    end
  end

  it "applies only the events after its checkpoint" do
    with_store do |store|
      log = SpecEvents::Log.new(store)
      store.append("s", 0_i64, note("one"))
      log.catch_up
      store.append("s", 1_i64, note("two"))
      log.catch_up
      log.catch_up
      log.lines.map(&.text).should eq(%w(one two))
      log.checkpoint.should eq(2_i64)
    end
  end

  it "reads past one batch" do
    with_store do |store|
      count = Shomen::Projection::BATCH + 1
      events = Array(Shomen::Event).new(count) { |index| SpecEvents::Noted.new("n#{index}") }
      store.append("s", 0_i64, events)
      log = SpecEvents::Log.new(store).catch_up
      log.lines.size.should eq(count)
      log.checkpoint.should eq(count.to_i64)
    end
  end

  it "rebuilds the read model after a restart" do
    path = File.tempname("shomen-store", ".sqlite3")
    begin
      first = Shomen::Store.new("sqlite3://#{path}")
      first.append("s", 0_i64, note("one"))
      first.append("s", 1_i64, note("two"))
      first.close

      second = Shomen::Store.new("sqlite3://#{path}")
      log = SpecEvents::Log.new(second).catch_up
      log.lines.map { |line| {line.text, line.version} }.should eq([{"one", 1_i64}, {"two", 2_i64}])
      second.close
    ensure
      remove_database(path)
    end
  end

  it "sees an event appended through another store on the same file" do
    with_store do |store, path|
      other = Shomen::Store.new("sqlite3://#{path}")
      log = SpecEvents::Log.new(store).catch_up
      other.append("s", 0_i64, note("elsewhere"))
      log.catch_up.lines.map(&.text).should eq(["elsewhere"])
      other.close
    end
  end

  it "stops before an event it cannot apply and retries it next time" do
    with_store do |store|
      store.append("s", 0_i64, [
        SpecEvents::Noted.new("a"), SpecEvents::Noted.new("b"), SpecEvents::Noted.new("c"),
      ] of Shomen::Event)
      log = SpecEvents::Log.new(store)
      log.fail_on = "b"
      expect_raises(Exception, "cannot apply b") { log.catch_up }
      log.checkpoint.should eq(1_i64)
      log.lines.map(&.text).should eq(["a"])

      log.fail_on = nil
      log.catch_up
      log.lines.map(&.text).should eq(%w(a b c))
      log.checkpoint.should eq(3_i64)
    end
  end
end
