require "../spec_helper"

describe "Shomen::Consumer#read" do
  store_it "yields at once for id 0" do |store|
    notes = SpecConsumers::Notes.new(store)
    store.append("s", 0_i64, note("one"))
    notes.read { |connection| connection.scalar("SELECT COUNT(*) FROM spec_notes").as(Int64) }.should eq(0_i64)
  end

  store_it "yields once the checkpoint reached the id" do |store|
    notes = SpecConsumers::Notes.new(store)
    store.append("s", 0_i64, note("one"))
    spawn { notes.run_once }
    texts = notes.read(1_i64, within: 5.seconds) do |connection|
      connection.query_all("SELECT text FROM spec_notes", as: String)
    end
    texts.should eq(%w(one))
  end

  store_it "raises Shomen::Unavailable when the checkpoint does not reach the id within the limit" do |store|
    notes = SpecConsumers::Notes.new(store)
    store.append("s", 0_i64, note("one"))
    expect_raises(Shomen::Unavailable, /\Aspec_notes did not reach event 1 within /) do
      notes.read(1_i64, within: 50.milliseconds) { |_| }
    end
  end

  it "raises Shomen::Unavailable within the limit while another fiber holds the file (sqlite3)" do
    with_store do |store|
      notes = SpecConsumers::Notes.new(store)
      notes.checkpoint
      store.append("s", 0_i64, note("one"))
      unavailable_while_held(store, notes)
    end
  end

  postgres_database_it "raises Shomen::Unavailable within the limit while another fiber holds the only connection (postgres)" do |url|
    uri = URI.parse(url)
    uri.query = "max_pool_size=1"
    store = Shomen::Store.new(uri.to_s)
    begin
      notes = SpecConsumers::Notes.new(store)
      notes.checkpoint
      store.append("s", 0_i64, note("one"))
      unavailable_while_held(store, notes)
    ensure
      store.close
    end
  end
end

# Holds the store's connection for a second while notes reads id 1 with a
# 50 ms limit, which must raise long before the connection comes back.
private def unavailable_while_held(store : Shomen::Store, notes : SpecConsumers::Notes) : Nil
  held = Channel(Nil).new
  released = Channel(Nil).new
  spawn do
    store.using_connection do |_|
      held.send(nil)
      sleep 1.second
    end
    released.send(nil)
  end
  held.receive
  started = Time.instant
  expect_raises(Shomen::Unavailable, /\Aspec_notes did not reach event 1 within /) do
    notes.read(1_i64, within: 50.milliseconds) { |_| }
  end
  (Time.instant - started).should be < 500.milliseconds
  released.receive
end

describe "a page that reads a projection kept in tables" do
  store_it "is a 503 document while the projection lags, and a 200 once it reached the id" do |store|
    notes = SpecConsumers::Notes.new(store)
    ConsumerRoutes.notes = notes
    begin
      store.append("s", 0_i64, note("one"))
      response = call_with(Shomen::Server.new, "GET", "/phase7/notes/1")
      response.status_code.should eq(503)
      response.body.should contain("<h1>Unavailable</h1>")
      response.body.should_not contain("<li>")
      notes.run_once.should eq(1)
      response = call_with(Shomen::Server.new, "GET", "/phase7/notes/1")
      response.status_code.should eq(200)
      response.body.should contain("<li>one</li>")
    ensure
      ConsumerRoutes.notes = nil
    end
  end
end
