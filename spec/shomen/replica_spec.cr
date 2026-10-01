require "../spec_helper"

private def texts(rows : Array(Shomen::Recorded)) : Array(String)
  rows.map { |row| row.event.as(SpecEvents::Noted).text }
end

private def with_replica_store(primary : String, replica : String, & : Shomen::Store ->) : Nil
  store = Shomen::Store.new(primary, replica: replica)
  begin
    yield store
  ensure
    store.close
  end
end

describe "Shomen::Store with a replica" do
  it "refuses a replica for a SQLite store" do
    path = File.tempname("shomen-store", ".sqlite3")
    begin
      expect_raises(ArgumentError, "a replica needs a postgres store") do
        Shomen::Store.new("sqlite3://#{path}", replica: "postgres://localhost/replica")
      end
      File.exists?(path).should be_false
    ensure
      remove_database(path)
    end
  end

  it "refuses a replica that is not Postgres" do
    expect_raises(ArgumentError, "replica URL must use postgres or postgresql, got \"sqlite3\"") do
      Shomen::Store.new("postgres://localhost/primary", replica: "sqlite3://./replica.sqlite3")
    end
    expect_raises(ArgumentError, /\Areplica URL is not valid/) do
      Shomen::Store.new("postgres://localhost/primary", replica: "postgres://localhost:x/replica")
    end
  end

  it "has no replica unless given one" do
    with_store { |store, _| store.replica?.should be_false }
  end

  postgres_database_it "creates no table in the replica's database" do |replica|
    PostgresSpec.with_database do |primary|
      with_replica_store(primary, replica) do |store|
        store.replica?.should be_true
        DB.open(replica) do |db|
          db.scalar("SELECT COUNT(*) FROM pg_tables WHERE tablename IN ('events', 'consumers')").as(Int64).should eq(0_i64)
        end
      end
    end
  end

  replica_it "reads the replica when asked to, and the primary otherwise" do |primary, replica|
    with_replica_store(primary, replica) do |store|
      store.append("s", 0_i64, note("copied"))
      PostgresSpec.copy(primary, replica, "events")
      store.append("s", 1_i64, note("lagging"))
      texts(store.read(after: 0_i64, replica: true)).should eq(%w(copied))
      texts(store.read(after: 0_i64)).should eq(%w(copied lagging))
      store.using_connection(replica: true, &.scalar("SELECT COUNT(*) FROM events").as(Int64)).should eq(1_i64)
      store.using_connection(&.scalar("SELECT COUNT(*) FROM events").as(Int64)).should eq(2_i64)
    end
  end

  replica_it "reads a checkpoint from the replica when asked to" do |primary, replica|
    with_replica_store(primary, replica) do |store|
      notes = SpecConsumers::Notes.new(store)
      notes.checkpoint
      PostgresSpec.copy(primary, replica, "consumers")
      store.append("s", 0_i64, note("one"))
      notes.run_once.should eq(1)
      store.checkpoint("spec_notes").should eq(1_i64)
      store.checkpoint("spec_notes", replica: true).should eq(0_i64)
    end
  end

  postgres_it "reads the primary for replica: true when it has no replica" do |store, _|
    store.append("s", 0_i64, note("one"))
    texts(store.read(after: 0_i64, replica: true)).should eq(%w(one))
    store.checkpoint("none", replica: true).should eq(0_i64)
    store.using_connection(replica: true, &.scalar("SELECT COUNT(*) FROM events").as(Int64)).should eq(1_i64)
  end

  replica_it "closes the replica's connections with the store" do |primary, replica|
    store = Shomen::Store.new(primary, replica: replica)
    store.read(after: 0_i64, replica: true)
    store.close
    # Postgres removes a backend shortly after its client leaves.
    DB.open(replica) do |db|
      wait_until do
        db.scalar("SELECT COUNT(*) FROM pg_stat_activity WHERE datname = current_database() AND pid <> pg_backend_pid()").as(Int64) == 0
      end
    end
  end
end

private def log_texts(log : SpecEvents::Log) : Array(String)
  log.lines.map(&.text)
end

describe "Shomen::Projection#catch_up with a replica" do
  replica_it "catches up from the replica" do |primary, replica|
    with_replica_store(primary, replica) do |store|
      store.append("s", 0_i64, note("copied"))
      PostgresSpec.copy(primary, replica, "events")
      store.append("s", 1_i64, note("lagging"))
      log_texts(SpecEvents::Log.new(store).catch_up).should eq(%w(copied))
    end
  end

  replica_it "does not read the primary once the replica reached the id" do |primary, replica|
    with_replica_store(primary, replica) do |store|
      store.append("s", 0_i64, noted(%w(one two three)))
      PostgresSpec.copy(primary, replica, "events", upto: 1_i64)
      spawn { PostgresSpec.copy(primary, replica, "events", upto: 2_i64) }
      log = SpecEvents::Log.new(store).catch_up(2_i64, within: 5.seconds)
      log_texts(log).should eq(%w(one two))
      log.checkpoint.should eq(2_i64)
    end
  end

  replica_it "catches up from the primary when the replica does not reach the id within the limit" do |primary, replica|
    with_replica_store(primary, replica) do |store|
      store.append("s", 0_i64, note("copied"))
      PostgresSpec.copy(primary, replica, "events")
      id = store.append("s", 1_i64, note("lagging"))
      started = Time.instant
      log_texts(SpecEvents::Log.new(store).catch_up(id, within: 50.milliseconds)).should eq(%w(copied lagging))
      (Time.instant - started).should be >= 50.milliseconds
    end
  end

  replica_it "lets a catch_up without an id go on while another waits for the replica" do |primary, replica|
    with_replica_store(primary, replica) do |store|
      log = SpecEvents::Log.new(store)
      id = store.append("s", 0_i64, note("lagging"))
      waiting = Channel(Nil).new
      spawn do
        log.catch_up(id, within: 5.seconds)
        waiting.send(nil)
      end
      Fiber.yield
      started = Time.instant
      log.catch_up
      (Time.instant - started).should be < 1.second
      PostgresSpec.copy(primary, replica, "events")
      waiting.receive
      log_texts(log).should eq(%w(lagging))
    end
  end

  postgres_it "ignores the id without a replica, as the primary has every append" do |store, _|
    store.append("s", 0_i64, note("one"))
    log_texts(SpecEvents::Log.new(store).catch_up(5_i64, within: 5.seconds)).should eq(%w(one))
  end
end

# Gives the replica the consumer's tables and its row, at checkpoint 0.
private def prepare_notes(replica : String) : Nil
  store = Shomen::Store.new(replica)
  begin
    SpecConsumers::Notes.new(store).checkpoint
  ensure
    store.close
  end
end

private def copy_notes(primary : String, replica : String) : Nil
  {"consumers", "spec_notes"}.each { |table| PostgresSpec.copy(primary, replica, table) }
end

private def read_notes(notes : SpecConsumers::Notes, id : Int64, within : Time::Span = 50.milliseconds) : Array(String)
  notes.read(id, within: within) do |connection|
    connection.query_all("SELECT text FROM spec_notes ORDER BY event_id", as: String)
  end
end

describe "Shomen::Consumer#read with a replica" do
  replica_it "reads the replica for id 0" do |primary, replica|
    prepare_notes(replica)
    with_replica_store(primary, replica) do |store|
      notes = SpecConsumers::Notes.new(store)
      store.append("s", 0_i64, note("one"))
      notes.run_once.should eq(1)
      read_notes(notes, 0_i64).should be_empty
    end
  end

  replica_it "reads the replica once its checkpoint reached the id" do |primary, replica|
    prepare_notes(replica)
    with_replica_store(primary, replica) do |store|
      notes = SpecConsumers::Notes.new(store)
      store.append("s", 0_i64, note("one"))
      notes.run_once.should eq(1)
      copy_notes(primary, replica)
      store.append("s", 1_i64, note("two"))
      notes.run_once.should eq(1)
      read_notes(notes, 1_i64).should eq(%w(one))
    end
  end

  replica_it "reads the primary when the replica does not reach the id within the limit and the primary did" do |primary, replica|
    prepare_notes(replica)
    with_replica_store(primary, replica) do |store|
      notes = SpecConsumers::Notes.new(store)
      store.append("s", 0_i64, note("one"))
      notes.run_once.should eq(1)
      copy_notes(primary, replica)
      id = store.append("s", 1_i64, note("two"))
      notes.run_once.should eq(1)
      read_notes(notes, id).should eq(%w(one two))
    end
  end

  replica_it "raises Shomen::Unavailable when neither the replica nor the primary reached the id" do |primary, replica|
    prepare_notes(replica)
    with_replica_store(primary, replica) do |store|
      notes = SpecConsumers::Notes.new(store)
      id = store.append("s", 0_i64, note("one"))
      expect_raises(Shomen::Unavailable, /\Aspec_notes did not reach event 1 within /) do
        read_notes(notes, id)
      end
    end
  end
end
