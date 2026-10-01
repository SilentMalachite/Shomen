require "../spec_helper"

private def receive_within(channel : Channel(Bool), within : Time::Span = 20.seconds) : Bool
  select
  when value = channel.receive
    value
  when timeout(within)
    raise "no answer within #{within}"
  end
end

# An adapter whose first polls fail a given number of times.
private class FlakyAdapter < Shomen::StoreAdapter
  property last : Int64 = 0_i64

  def initialize(@failures : Int32)
  end

  def key : String
    "flaky"
  end

  def append(stream : String, expected_version : Int64, rows : Array(Row)) : Int64
    raise "not used"
  end

  def read(after : Int64, limit : Int32) : Array(Stored)
    [] of Stored
  end

  def last_id : Int64
    if @failures > 0
      @failures -= 1
      raise "the database is away"
    end
    @last
  end

  def close : Nil
  end
end

# An adapter that notifies and lets the spec decide when its listening
# connection opens. interrupt_listen ends a listen only once it is
# connected, as terminating a backend that does not exist yet does nothing.
private class GatedAdapter < Shomen::StoreAdapter
  getter entered = Channel(Nil).new(1)
  getter opened = Channel(Nil).new(1)
  getter ended = Channel(Nil).new(1)
  property interrupt_hangs = false
  @connect = Channel(Nil).new(1)
  @interrupted = Channel(Nil).new(1)
  @connected = Atomic(Bool).new(false)

  def key : String
    "gated"
  end

  def append(stream : String, expected_version : Int64, rows : Array(Row)) : Int64
    raise "not used"
  end

  def read(after : Int64, limit : Int32) : Array(Stored)
    [] of Stored
  end

  def last_id : Int64
    0_i64
  end

  def close : Nil
  end

  def notifies? : Bool
    true
  end

  # Lets the listen that waits for it connect.
  def connect : Nil
    @connect.send(nil)
  end

  def listen(on_id : Int64 -> Nil) : Nil
    @entered.send(nil)
    @connect.receive
    @connected.set(true)
    @opened.send(nil)
    @interrupted.receive
    raise IO::EOFError.new
  ensure
    @ended.send(nil)
  end

  def interrupt_listen : Nil
    Channel(Nil).new.receive if interrupt_hangs
    @interrupted.send(nil) if @connected.swap(false)
  end
end

# An adapter whose polls wait until the spec opens a gate, so a poll can
# be in progress when stop runs.
private class BlockingAdapter < Shomen::StoreAdapter
  getter calls_after_close = 0
  getter entered = Channel(Nil).new(1)
  @gate = Channel(Nil).new
  @closed = false

  def key : String
    "blocking"
  end

  def append(stream : String, expected_version : Int64, rows : Array(Row)) : Int64
    raise "not used"
  end

  def read(after : Int64, limit : Int32) : Array(Stored)
    [] of Stored
  end

  def last_id : Int64
    select
    when @entered.send(nil)
    else
    end
    @gate.receive?
    @calls_after_close += 1 if @closed
    0_i64
  end

  # Lets every poll, the one waiting and any later one, return.
  def open_gate : Nil
    @gate.close
  end

  def close : Nil
    @closed = true
  end
end

private def within(channel : Channel(Nil), limit : Time::Span = 10.seconds) : Bool
  select
  when channel.receive
    true
  when timeout(limit)
    false
  end
end

describe Shomen::AppendWatcher do
  it "waits for a poll in progress before stop returns, and does not poll after" do
    adapter = BlockingAdapter.new
    watcher = Shomen::AppendWatcher.new(adapter, Shomen::AppendSignal.new, 1.hour, stop_limit: 5.seconds)
    within(adapter.entered).should be_true
    done = Channel(Nil).new(1)
    spawn do
      watcher.stop
      done.send(nil)
    end
    10.times { Fiber.yield }
    select
    when done.receive
      fail "stop returned while a poll was in progress"
    else
    end
    adapter.open_gate
    within(done, 2.seconds).should be_true
    adapter.close
    100.times { Fiber.yield }
    adapter.calls_after_close.should eq(0)
  end

  it "returns from stop within its limit when the interrupt hangs" do
    adapter = GatedAdapter.new
    adapter.interrupt_hangs = true
    watcher = Shomen::AppendWatcher.new(adapter, Shomen::AppendSignal.new, 1.hour, stop_limit: 100.milliseconds)
    adapter.connect
    within(adapter.opened).should be_true
    done = Channel(Nil).new(1)
    spawn do
      watcher.stop
      done.send(nil)
    end
    within(done, 2.seconds).should be_true
  end

  it "closes a listening connection that opens after stop gave up" do
    adapter = GatedAdapter.new
    watcher = Shomen::AppendWatcher.new(adapter, Shomen::AppendSignal.new, 1.hour, stop_limit: 50.milliseconds)
    within(adapter.entered).should be_true
    watcher.stop
    adapter.connect
    within(adapter.opened).should be_true
    within(adapter.ended).should be_true
  end

  it "backs off by doubling up to the interval, and starts again after a connection that lasted" do
    first = Shomen::AppendWatcher::RETRY_FIRST
    Shomen::AppendWatcher.backoff(first, 1.millisecond, 1.second).should eq({first, first * 2})
    Shomen::AppendWatcher.backoff(first * 4, 1.millisecond, 1.second).should eq({first * 4, first * 8})
    Shomen::AppendWatcher.backoff(800.milliseconds, 1.millisecond, 1.second).should eq({800.milliseconds, 1.second})
    Shomen::AppendWatcher.backoff(1.second, 1.millisecond, 1.second).should eq({1.second, 1.second})
    Shomen::AppendWatcher.backoff(first * 8, 1.minute, 1.second).should eq({first, first * 2})
  end

  it "leaves no SQLite file behind after the store closes and the file is removed" do
    path = File.tempname("shomen-store", ".sqlite3")
    store = Shomen::Store.new("sqlite3://#{path}", poll_interval: 1.millisecond)
    store.append("a", 0_i64, note("1"))
    store.wait_for_append(after: 0_i64, within: 1.millisecond).should be_true
    store.close
    remove_database(path)
    100.times { Fiber.yield }
    File.exists?(path).should be_false
  ensure
    remove_database(path) if path
  end

  postgres_it "leaves no connection after the store closes" do |_, url|
    other = Shomen::Store.new(url, poll_interval: 1.millisecond)
    other.append("a", 0_i64, note("1"))
    other.wait_for_append(after: 0_i64, within: 1.millisecond).should be_true
    other.close
    DB.open(url) do |db|
      # The store that store_it opened keeps its own pool; count only
      # connections other than that pool's and this one.
      wait_until(10.seconds) do
        db.scalar("SELECT count(*) FROM pg_stat_activity WHERE datname = current_database() AND pid <> pg_backend_pid() AND application_name LIKE 'shomen-%'").as(Int64) == 0
      end
    end
  end

  postgres_it "interrupts without a pooled connection" do |_, url|
    uri = URI.parse(url)
    uri.query = "max_pool_size=1"
    store = Shomen::Store.new(uri.to_s, poll_interval: 1.hour)
    begin
      store.wait_for_append(after: 0_i64, within: 1.millisecond)
      DB.open(url) { |db| wait_until(10.seconds) { PostgresSpec.listeners(db).size == 1 } }
      adapter = store.@adapter.as(Shomen::PostgresAdapter)
      held = Channel(Nil).new
      release = Channel(Nil).new
      spawn do
        adapter.@db.using_connection do
          held.send(nil)
          release.receive
        end
      end
      held.receive
      done = Channel(Nil).new(1)
      spawn do
        adapter.interrupt_listen
        done.send(nil)
      end
      within(done, 3.seconds).should be_true
      release.send(nil)
    ensure
      store.close
    end
  end

  it "keeps polling after a poll fails, and logs the failure" do
    signal = Shomen::AppendSignal.new
    adapter = FlakyAdapter.new(failures: 2)
    adapter.last = 5_i64
    Log.capture("shomen") do |logs|
      watcher = Shomen::AppendWatcher.new(adapter, signal, 1.millisecond)
      begin
        signal.wait(after: 0_i64, within: 10.seconds).should be_true
        signal.last.should eq(5_i64)
        logs.check(:warn, "could not poll for appends")
      ensure
        watcher.stop
      end
    end
  end

  it "starts without touching the database, so a failing first poll does not raise" do
    signal = Shomen::AppendSignal.new
    watcher = Shomen::AppendWatcher.new(FlakyAdapter.new(failures: 1), signal, 1.hour)
    watcher.stop
  end

  store_it "learns of an event another writer committed at the next poll" do |_, url|
    store = Shomen::Store.new(url, poll_interval: 20.milliseconds)
    begin
      woke = Channel(Bool).new(1)
      spawn { woke.send(store.wait_for_append(after: 0_i64, within: 20.seconds)) }
      wait_until { store.@signal.waiting == 1 }
      insert_unannounced(url, "elsewhere")
      receive_within(woke).should be_true
      store.last_appended.should eq(1_i64)
    ensure
      store.close
    end
  end

  store_it "starts watching only when something waits, and stops when the store that started it closes" do |_, url|
    store = Shomen::Store.new(url)
    watcher = nil
    begin
      store.append("a", 0_i64, note("1"))
      store.read(after: 0_i64)
      store.@watcher.should be_nil
      store.wait_for_append(after: 0_i64, within: 1.millisecond).should be_true
      watcher = store.@watcher
      watcher.should_not be_nil
      store.close
      watcher.try(&.stopped?).should be_true
    ensure
      store.close unless watcher.try(&.stopped?)
    end
  end

  store_it "starts watching again for a store that waits after the watching store closed" do |_, url|
    first = Shomen::Store.new(url, poll_interval: 20.milliseconds)
    second = Shomen::Store.new(url, poll_interval: 20.milliseconds)
    begin
      first.wait_for_append(after: 0_i64, within: 1.millisecond).should be_false
      second.wait_for_append(after: 0_i64, within: 1.millisecond).should be_false
      second.@watcher.should be_nil
      first.close
      woke = Channel(Bool).new(1)
      spawn { woke.send(second.wait_for_append(after: 0_i64, within: 20.seconds)) }
      wait_until { second.@signal.waiting == 1 }
      insert_unannounced(url, "elsewhere")
      receive_within(woke).should be_true
      second.@watcher.should_not be_nil
    ensure
      second.close
    end
  end

  store_it "keeps the shared watcher running when a store that did not start it closes" do |_, url|
    first = Shomen::Store.new(url, poll_interval: 20.milliseconds)
    second = Shomen::Store.new(url, poll_interval: 20.milliseconds)
    begin
      first.wait_for_append(after: 0_i64, within: 1.millisecond).should be_false
      second.wait_for_append(after: 0_i64, within: 1.millisecond).should be_false
      second.@watcher.should be_nil
      second.close
      watcher = first.@watcher
      watcher.should_not be_nil
      watcher.try(&.stopped?).should be_false
      woke = Channel(Bool).new(1)
      spawn { woke.send(first.wait_for_append(after: 0_i64, within: 20.seconds)) }
      wait_until { first.@signal.waiting == 1 }
      insert_unannounced(url, "elsewhere")
      receive_within(woke).should be_true
    ensure
      first.close
    end
  end

  store_it "does not start watching after the store closed" do |_, url|
    store = Shomen::Store.new(url)
    store.close
    store.wait_for_append(after: 0_i64, within: 1.millisecond).should be_false
    store.@watcher.should be_nil
  end

  it "refuses a poll interval that is not positive" do
    path = File.tempname("shomen-store", ".sqlite3")
    begin
      expect_raises(ArgumentError, "poll_interval must be positive") do
        Shomen::Store.new("sqlite3://#{path}", poll_interval: 0.seconds)
      end
      File.exists?(path).should be_false
    ensure
      remove_database(path)
    end
  end

  postgres_it "wakes a waiting fiber on the notification of an append through another process, before any poll" do |_, url|
    store = Shomen::Store.new(url, poll_interval: 1.hour)
    begin
      woke = Channel(Bool).new(1)
      spawn { woke.send(store.wait_for_append(after: 0_i64, within: 20.seconds)) }
      DB.open(url) { |db| wait_until(10.seconds) { PostgresSpec.listeners(db).size == 1 } }
      append_elsewhere(url, "elsewhere", 1)
      receive_within(woke).should be_true
      store.last_appended.should eq(1_i64)
    ensure
      store.close
    end
  end

  postgres_it "listens on one connection of its own for every store on the database in this process" do |store, url|
    other = Shomen::Store.new(url)
    begin
      store.wait_for_append(after: 0_i64, within: 1.millisecond)
      other.wait_for_append(after: 0_i64, within: 1.millisecond)
      other.@watcher.should be_nil
      DB.open(url) { |db| wait_until(10.seconds) { PostgresSpec.listeners(db).size == 1 } }
    ensure
      other.close
    end
  end

  postgres_it "connects again and catches up at once when the listening connection drops" do |_, url|
    store = Shomen::Store.new(url, poll_interval: 1.hour)
    DB.open(url) do |db|
      begin
        store.wait_for_append(after: 0_i64, within: 1.millisecond).should be_false
        wait_until(10.seconds) { PostgresSpec.listeners(db).size == 1 }
        first = PostgresSpec.listeners(db)
        insert_unannounced(url, "unannounced")
        woke = Channel(Bool).new(1)
        spawn { woke.send(store.wait_for_append(after: 0_i64, within: 20.seconds)) }
        wait_until { store.@signal.waiting == 1 }
        db.exec("SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = current_database() AND application_name LIKE 'shomen-listen-%'")
        receive_within(woke).should be_true
        store.last_appended.should eq(1_i64)
        wait_until(10.seconds) do
          now = PostgresSpec.listeners(db)
          now.size == 1 && now != first
        end
      ensure
        store.close
      end
    end
  end

  postgres_it "closes its listening connection when the store closes" do |_, url|
    other = Shomen::Store.new(url)
    other.wait_for_append(after: 0_i64, within: 1.millisecond)
    DB.open(url) do |db|
      wait_until(10.seconds) { PostgresSpec.listeners(db).size == 1 }
      other.close
      wait_until(10.seconds) { PostgresSpec.listeners(db).empty? }
    end
  end

  postgres_it "closes a listening connection that was still opening when the store closed" do |_, url|
    other = Shomen::Store.new(url)
    other.wait_for_append(after: 0_i64, within: 1.millisecond)
    other.close
    DB.open(url) do |db|
      wait_until(10.seconds) do
        db.scalar("SELECT count(*) FROM pg_stat_activity WHERE datname = current_database() AND application_name LIKE 'shomen-listen-%'").as(Int64) == 0
      end
    end
  end

  postgres_it "ignores a notification on its channel that carries no id" do |_, url|
    store = Shomen::Store.new(url, poll_interval: 1.hour)
    DB.open(url) do |db|
      begin
        woke = Channel(Bool).new(1)
        spawn { woke.send(store.wait_for_append(after: 0_i64, within: 20.seconds)) }
        wait_until(10.seconds) { PostgresSpec.listeners(db).size == 1 }
        first = PostgresSpec.listeners(db)
        db.exec("SELECT pg_notify($1, $2)", Shomen::PostgresAdapter::CHANNEL, "not an id")
        append_elsewhere(url, "elsewhere", 1)
        receive_within(woke).should be_true
        store.last_appended.should eq(1_i64)
        PostgresSpec.listeners(db).should eq(first)
      ensure
        store.close
      end
    end
  end
end
