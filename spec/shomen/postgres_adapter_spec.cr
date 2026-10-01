require "../spec_helper"

private def with_query(url : String, name : String, value : String) : String
  uri = URI.parse(url)
  params = uri.query_params
  params[name] = value
  uri.query_params = params
  uri.to_s
end

private def pool(store : Shomen::Store) : DB::Pool(DB::Connection)
  store.@adapter.as(Shomen::PostgresAdapter).@db.pool
end

describe Shomen::PostgresAdapter do
  it "refuses a URL without a database name before it connects" do
    expect_raises(ArgumentError, "store URL must name a database") { Shomen::Store.new("postgres://localhost") }
    expect_raises(ArgumentError, "store URL must name a database") { Shomen::Store.new("postgresql://localhost/") }
  end

  it "keys a URL by the port and host the driver connects to" do
    with_env({"PGPORT" => nil, "PGHOST" => nil}) do
      Shomen::PostgresAdapter.key(URI.parse("postgres://localhost/app")).should eq("postgres://localhost:5432/app")
      Shomen::PostgresAdapter.key(URI.parse("postgres://localhost/app?port=5433")).should eq("postgres://localhost:5433/app")
    end
    with_env({"PGPORT" => "5433", "PGHOST" => "db.example"}) do
      key = Shomen::PostgresAdapter.key(URI.parse("postgres://db.example:5433/app"))
      key.should eq("postgres://db.example:5433/app")
      Shomen::PostgresAdapter.key(URI.parse("postgres://db.example/app")).should eq(key)
      Shomen::PostgresAdapter.key(URI.parse("postgres:///app")).should eq(key)
    end
  end

  postgres_it "creates the events table with BIGINT integers and an identity cached one at a time" do |_, url|
    DB.open(url) do |db|
      columns = db.query_all(
        "SELECT column_name, data_type FROM information_schema.columns WHERE table_name = 'events' ORDER BY ordinal_position",
        as: {String, String},
      )
      columns.should eq([
        {"id", "bigint"}, {"stream", "text"}, {"version", "bigint"},
        {"type", "text"}, {"payload", "text"}, {"at", "text"},
      ])
      db.scalar("SELECT seqcache FROM pg_sequence WHERE seqrelid = pg_get_serial_sequence('events', 'id')::regclass").should eq(1_i64)
    end
  end

  postgres_it "accepts the postgresql scheme for the same database" do |store, url|
    uri = URI.parse(url)
    uri.scheme = "postgresql"
    other = Shomen::Store.new(uri.to_s)
    begin
      other.append("s", 0_i64, note("x"))
      store.read(after: 0_i64).map(&.stream).should eq(["s"])
    ensure
      other.close
    end
  end

  postgres_it "shares the append signal between a URL without a port and one with port 5432" do |store, url|
    uri = URI.parse(url)
    case uri.port
    when nil  then uri.port = 5432
    when 5432 then uri.port = nil
    else           pending!("SHOMEN_SPEC_POSTGRES names port #{uri.port}")
    end
    pending!("PGPORT is #{ENV["PGPORT"]}") if ENV.fetch("PGPORT", "5432") != "5432"
    other = Shomen::Store.new(uri.to_s)
    begin
      key = store.@adapter.as(Shomen::PostgresAdapter).key
      key.should end_with(":5432#{uri.path}")
      other.@adapter.as(Shomen::PostgresAdapter).key.should eq(key)
      other.append("s", 0_i64, note("x"))
      store.last_appended.should eq(1_i64)
    ensure
      other.close
    end
  end

  postgres_it "bounds the pool at 10 connections unless the URL sets it" do |store, url|
    pool(store).@max_pool_size.should eq(10)
    pool(store).@max_idle_pool_size.should eq(10)
    other = Shomen::Store.new(with_query(url, "max_pool_size", "3"))
    begin
      pool(other).@max_pool_size.should eq(3)
      pool(other).@max_idle_pool_size.should eq(3)
    ensure
      other.close
    end
  end

  postgres_database_it "opens one events table when stores start at once on an empty database" do |url|
    done = Channel(Shomen::Store | Exception).new
    4.times do
      spawn do
        done.send(Shomen::Store.new(url))
      rescue ex
        done.send(ex)
      end
    end
    results = Array(Shomen::Store | Exception).new(4) { done.receive }
    results.each { |result| result.close if result.is_a?(Shomen::Store) }
    results.compact_map(&.as?(Exception)).map(&.message).should be_empty
    DB.open(url) { |db| db.scalar("SELECT count(*) FROM pg_tables WHERE tablename = 'events'").should eq(1_i64) }
  end

  postgres_it "writes none of the events when a later one fails" do |store, url|
    DB.open(url) { |db| db.exec(%(ALTER TABLE events ADD CONSTRAINT bad CHECK (payload NOT LIKE '%"bad"%'))) }
    expect_raises(PQ::PQError, "bad") do
      store.append("s", 0_i64, [SpecEvents::Noted.new("ok"), SpecEvents::Noted.new("bad")] of Shomen::Event)
    end
    store.read(after: 0_i64).should be_empty
    store.append("s", 0_i64, note("after"))
    store.read(after: 0_i64).map(&.version).should eq([1_i64])
  end

  postgres_it "makes an append from another process wait while an append transaction is open after its insert" do |_, url|
    worker = Process.new(
      Workers.binary("spec/support/store_worker.cr"), [url, "worker", "1", "wait"],
      input: :pipe, output: :pipe, error: :inherit,
    )
    begin
      worker.output.gets.should eq("ready")
      key = Shomen::PostgresAdapter::LOCK_KEY
      waiting = <<-SQL
        SELECT count(*) FROM pg_locks
        WHERE locktype = 'advisory' AND NOT granted AND objsubid = 1
          AND database = (SELECT oid FROM pg_database WHERE datname = current_database())
          AND classid = $1::bigint::oid AND objid = $2::bigint::oid
        SQL
      DB.open(url) do |db|
        db.using_connection do |open|
          # The statements an append runs, stopped before its COMMIT.
          open.exec("BEGIN")
          open.exec(Shomen::PostgresAdapter::LOCK, key)
          open.scalar(Shomen::PostgresAdapter::INSERT, "open", 1_i64, "spec.noted", %({"text":"open"}), "2026-09-29T00:00:00Z")
          worker.input.puts("go")
          worker.input.flush
          wait_until { db.scalar(waiting, key >> 32, key & 0xffffffff_i64) == 1_i64 }
          worker.terminated?.should be_false
          open.exec("COMMIT")
        end
        worker.wait.success?.should be_true
        db.query_all("SELECT id, stream FROM events ORDER BY id", as: {Int64, String}).should eq([
          {1_i64, "open"}, {2_i64, "worker"},
        ])
      end
    ensure
      unless worker.terminated?
        worker.terminate
        worker.wait
      end
    end
  end

  postgres_it "gives a projection that follows its checkpoint every event once, in id order, while two processes append" do |store, url|
    binary = Workers.binary("spec/support/store_worker.cr")
    workers = %w(left right).map { |stream| Process.new(binary, [url, stream, "300"], error: :inherit) }
    begin
      log = SpecEvents::Log.new(store)
      wait_until(60.seconds) { log.catch_up.lines.size >= 600 }
      workers.each { |worker| worker.wait.success?.should be_true }
      ids = log.catch_up.lines.map(&.id)
      ids.size.should eq(600)
      ids.should eq(ids.sort.uniq)
      ids.should eq(store.read(after: 0_i64, limit: 1000).map(&.id))
    ensure
      workers.each do |worker|
        unless worker.terminated?
          worker.terminate
          worker.wait
        end
      end
    end
  end

  postgres_it "notifies its channel with the last id once an append commits, and not for a conflict" do |store, url|
    payloads = Channel(String).new(4)
    listener = PG.connect_listen(url, Shomen::PostgresAdapter::CHANNEL) { |notification| payloads.send(notification.payload) }
    begin
      store.append("a", 0_i64, [SpecEvents::Noted.new("1"), SpecEvents::Noted.new("2")] of Shomen::Event)
      expect_raises(Shomen::Conflict) { store.append("a", 0_i64, note("3")) }
      store.append("b", 0_i64, note("4"))
      received = Array.new(2) do
        select
        when payload = payloads.receive
          payload
        when timeout(5.seconds)
          fail "no notification within 5 seconds"
        end
      end
      received.should eq(["2", "3"])
    ensure
      listener.close
    end
  end
end
