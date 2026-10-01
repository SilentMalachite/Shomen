require "../spec_helper"

# Writes the same key twice, so its second statement fails in SQL.
private class Duplicate < Shomen::Consumer
  def name : String
    "spec_duplicate"
  end

  def create_tables(connection : DB::Connection) : Nil
    connection.exec("CREATE TABLE IF NOT EXISTS spec_duplicate (a TEXT UNIQUE)")
  end

  def write(recorded : Shomen::Recorded, connection : DB::Connection) : Nil
    2.times { connection.exec("INSERT INTO spec_duplicate (a) VALUES ($1)", "same") }
  end
end

# Writes the same key for every event and rescues the violation itself.
private class Forgiving < Shomen::Consumer
  def name : String
    "spec_forgiving"
  end

  def create_tables(connection : DB::Connection) : Nil
    connection.exec("CREATE TABLE IF NOT EXISTS spec_forgiving (a TEXT UNIQUE)")
  end

  def write(recorded : Shomen::Recorded, connection : DB::Connection) : Nil
    2.times do
      connection.exec("SAVEPOINT forgiving")
      begin
        connection.exec("INSERT INTO spec_forgiving (a) VALUES ($1)", "same")
      rescue
        connection.exec("ROLLBACK TO forgiving")
      end
    end
  end
end

private class Nameless < Shomen::Consumer
  def name : String
    ""
  end
end

# Records the idle limit of the transaction its writes run in.
private class IdleLimit < Shomen::Consumer
  getter shown = [] of String

  def name : String
    "spec_idle_limit"
  end

  def write(recorded : Shomen::Recorded, connection : DB::Connection) : Nil
    @shown << connection.scalar("SHOW idle_in_transaction_session_timeout").as(String)
  end
end

describe Shomen::Consumer do
  store_it "applies the events after its checkpoint and commits the checkpoint with its writes" do |store|
    notes = SpecConsumers::Notes.new(store)
    store.append("s", 0_i64, noted(%w(one two)))
    notes.run_once.should eq(2)
    notes.checkpoint.should eq(2_i64)
    store.append("s", 2_i64, noted(%w(three)))
    notes.run_once.should eq(1)
    notes.run_once.should eq(0)
    notes.texts.should eq(%w(one two three))
    notes.checkpoint.should eq(3_i64)
  end

  store_it "commits at most one batch at a time" do |store|
    notes = SpecConsumers::Notes.new(store)
    store.append("s", 0_i64, noted(Array.new(Shomen::Consumer::BATCH + 1) { |index| "n#{index}" }))
    notes.run_once.should eq(Shomen::Consumer::BATCH)
    notes.checkpoint.should eq(Shomen::Consumer::BATCH.to_i64)
    notes.run_once.should eq(1)
  end

  store_it "leaves out both the writes and the checkpoint of a failing event, and keeps the events before it" do |store|
    notes = SpecConsumers::Notes.new(store)
    notes.fail_write = "two"
    store.append("s", 0_i64, noted(%w(one two three)))
    expect_raises(Exception, "cannot write two") { notes.run_once }
    notes.texts.should eq(%w(one))
    notes.checkpoint.should eq(1_i64)
    notes.fail_write = nil
    notes.run_once.should eq(2)
    notes.texts.should eq(%w(one two three))
  end

  store_it "stops a batch at a failing reaction and does not skip the event" do |store|
    notes = SpecConsumers::Notes.new(store)
    notes.fail_react = "two"
    store.append("s", 0_i64, noted(%w(one two)))
    expect_raises(Exception, "cannot react two") { notes.run_once }
    notes.checkpoint.should eq(1_i64)
    notes.texts.should eq(%w(one))
    notes.fail_react = nil
    notes.run_once.should eq(1)
    notes.reacted.should eq(%w(one two))
  end

  store_it "fails on an event it cannot decode, after committing the events before it" do |store|
    notes = SpecConsumers::Notes.new(store)
    store.append("s", 0_i64, noted(%w(one)))
    store.using_connection do |connection|
      connection.exec(
        "INSERT INTO events (stream, version, type, payload, at) VALUES ($1, $2, $3, $4, $5)",
        "other", 1_i64, "spec.unknown", "{}", "2026-10-01T00:00:00Z",
      )
    end
    store.append("s", 1_i64, noted(%w(three)))
    expect_raises(ArgumentError, %(unknown event type "spec.unknown")) { notes.run_once }
    notes.checkpoint.should eq(1_i64)
    notes.texts.should eq(%w(one))
  end

  store_it "creates its tables and its checkpoint row before the first batch" do |store|
    notes = SpecConsumers::Notes.new(store)
    notes.checkpoint.should eq(0_i64)
    notes.texts.should be_empty
  end

  it "rejects an empty name" do
    with_store do |store|
      expect_raises(ArgumentError, "consumer name must not be empty") { Nameless.new(store).run_once }
    end
  end

  store_it "lets the store close after a write failed in SQL" do |_, url|
    store = Shomen::Store.new(url)
    duplicate = Duplicate.new(store)
    store.append("s", 0_i64, noted(%w(one)))
    expect_raises(Exception) { duplicate.run_once }
    duplicate.checkpoint.should eq(0_i64)
    store.close
  end

  store_it "lets the store close after a write rescued its own SQL failure" do |_, url|
    store = Shomen::Store.new(url)
    forgiving = Forgiving.new(store)
    store.append("s", 0_i64, noted(%w(one)))
    forgiving.run_once.should eq(1)
    forgiving.checkpoint.should eq(1_i64)
    store.close
  end

  postgres_it "skips a batch while another process holds its checkpoint" do |store, url|
    notes = SpecConsumers::Notes.new(store)
    notes.checkpoint
    store.append("s", 0_i64, noted(%w(one)))
    DB.open(url) do |db|
      db.using_connection do |connection|
        connection.exec("BEGIN")
        connection.query_one("SELECT checkpoint FROM consumers WHERE name = $1 FOR UPDATE", "spec_notes", as: Int64)
        notes.run_once.should eq(0)
        connection.exec("ROLLBACK")
      end
    end
    notes.texts.should be_empty
    notes.run_once.should eq(1)
  end

  postgres_it "limits how long a batch's transaction may stay idle" do |store|
    consumer = IdleLimit.new(store)
    store.append("s", 0_i64, noted(%w(one)))
    consumer.run_once.should eq(1)
    consumer.shown.should eq(["1min"])
  end

  it "rolls back its writes when another process moved the checkpoint during its reactions (sqlite3)" do
    with_store do |store, path|
      notes = SpecConsumers::Notes.new(store)
      notes.checkpoint
      store.append("s", 0_i64, noted(%w(one two)))
      notes.on_react = ->(_recorded : Shomen::Recorded) {
        DB.open("sqlite3://#{path}") { |db| db.exec("UPDATE consumers SET checkpoint = 2 WHERE name = 'spec_notes'") }
        nil
      }
      notes.run_once.should eq(0)
      notes.texts.should be_empty
      notes.checkpoint.should eq(2_i64)
    end
  end
end
