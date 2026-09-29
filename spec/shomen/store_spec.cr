require "../spec_helper"
require "file_utils"

private def texts(rows : Array(Shomen::Recorded)) : Array(String)
  rows.map { |row| row.event.as(SpecEvents::Noted).text }
end

describe Shomen::Store do
  it "numbers each stream from 1 and orders ids across streams" do
    with_store do |store|
      store.append("a", 0_i64, note("a1"))
      store.append("b", 0_i64, note("b1"))
      store.append("a", 1_i64, [SpecEvents::Noted.new("a2"), SpecEvents::Noted.new("a3")] of Shomen::Event)
      rows = store.read(after: 0_i64)
      rows.map { |row| {row.id, row.stream, row.version} }.should eq([
        {1_i64, "a", 1_i64}, {2_i64, "b", 1_i64}, {3_i64, "a", 2_i64}, {4_i64, "a", 3_i64},
      ])
      texts(rows).should eq(%w(a1 b1 a2 a3))
    end
  end

  it "reads only the events after a given id, up to the limit" do
    with_store do |store|
      5.times { |index| store.append("s", index.to_i64, note("n#{index}")) }
      store.read(after: 2_i64, limit: 2).map(&.id).should eq([3_i64, 4_i64])
      store.read(after: 5_i64).should be_empty
    end
  end

  it "appends two rows when the same command is handled twice" do
    with_store do |store|
      2.times do |version|
        events = SpecEvents::Note.new("same").call.as(Array(Shomen::Event))
        store.append("s", version.to_i64, events)
      end
      rows = store.read(after: 0_i64)
      rows.map(&.version).should eq([1_i64, 2_i64])
      texts(rows).should eq(%w(same same))
    end
  end

  it "raises Conflict and adds no row when two appends expect the same version" do
    with_store do |store|
      store.append("s", 0_i64, note("first"))
      expect_raises(Shomen::Conflict, "stream s is at version 1, expected 0") do
        store.append("s", 0_i64, note("second"))
      end
      texts(store.read(after: 0_i64)).should eq(["first"])
    end
  end

  it "raises Conflict and adds no row when the expected version is ahead" do
    with_store do |store|
      expect_raises(Shomen::Conflict, "stream s is at version 0, expected 3") do
        store.append("s", 3_i64, note("ahead"))
      end
      store.read(after: 0_i64).should be_empty
    end
  end

  it "stays usable and closes cleanly after a conflict" do
    with_store do |store|
      store.append("s", 0_i64, note("one"))
      expect_raises(Shomen::Conflict) { store.append("s", 0_i64, note("two")) }
      store.append("s", 1_i64, note("two"))
      texts(store.read(after: 0_i64)).should eq(%w(one two))
      store.close
    end
  end

  it "does nothing for an empty list of events" do
    with_store do |store|
      store.append("s", 7_i64, [] of Shomen::Event)
      store.read(after: 0_i64).should be_empty
    end
  end

  it "rejects an empty stream name and a negative version" do
    with_store do |store|
      expect_raises(ArgumentError) { store.append("", 0_i64, note("x")) }
      expect_raises(ArgumentError) { store.append("s", -1_i64, note("x")) }
    end
  end

  it "writes the declared type, the JSON payload, and the time to the second" do
    with_store do |store, path|
      at = Time.utc(2026, 9, 29, 1, 2, 3, nanosecond: 500_000_000)
      store.append("s", 0_i64, [SpecEvents::Noted.new("x", at)] of Shomen::Event)
      DB.open("sqlite3://#{path}") do |db|
        type, payload, stored_at = db.query_one("SELECT type, payload, at FROM events", as: {String, String, String})
        type.should eq("spec.noted")
        JSON.parse(payload)["text"].as_s.should eq("x")
        stored_at.should eq("2026-09-29T01:02:03Z")
      end
      store.read(after: 0_i64).first.event.at.should eq(Time.utc(2026, 9, 29, 1, 2, 3))
    end
  end

  it "raises with the type name for a row whose type no event declares" do
    with_store do |store, path|
      DB.open("sqlite3://#{path}") do |db|
        db.exec("INSERT INTO events (stream, version, type, payload, at) VALUES ('s', 1, 'gone', '{}', '2026-09-29T00:00:00Z')")
      end
      expect_raises(ArgumentError, %(unknown event type "gone")) { store.read(after: 0_i64) }
    end
  end

  it "creates a missing directory for a relative path and uses WAL" do
    dir = File.tempname("shomen-store-dir")
    Dir.mkdir(dir)
    begin
      Dir.cd(dir) do
        store = Shomen::Store.new("sqlite3://./var/shomen.sqlite3")
        store.append("s", 0_i64, note("x"))
        File.exists?("var/shomen.sqlite3").should be_true
        File.exists?("var/shomen.sqlite3-wal").should be_true
        store.close
      end
    ensure
      FileUtils.rm_rf(dir)
    end
  end

  it "stays usable and closes cleanly after another writer held the lock past the busy timeout" do
    path = File.tempname("shomen-store", ".sqlite3")
    begin
      store = Shomen::Store.new("sqlite3://#{path}?busy_timeout=50")
      DB.open("sqlite3://#{path}") do |db|
        db.using_connection do |blocker|
          blocker.exec("BEGIN IMMEDIATE")
          expect_raises(SQLite3::Exception, "database is locked") { store.append("s", 0_i64, note("x")) }
          blocker.exec("ROLLBACK")
        end
      end
      store.read(after: 0_i64).should be_empty
      store.close
    ensure
      remove_database(path)
    end
  end

  it "keeps the insert error and closes cleanly when SQLite rolled the transaction back" do
    with_store do |store, path|
      DB.open("sqlite3://#{path}") do |db|
        db.exec("CREATE TRIGGER boom BEFORE INSERT ON events WHEN NEW.stream = 'boom' BEGIN SELECT RAISE(ROLLBACK, 'boom'); END")
      end
      expect_raises(SQLite3::Exception, "boom") { store.append("boom", 0_i64, note("x")) }
      store.append("s", 0_i64, note("y"))
      texts(store.read(after: 0_i64)).should eq(["y"])
      store.close
    end
  end

  it "refuses a URL that is not a sqlite3 file" do
    expect_raises(ArgumentError) { Shomen::Store.new("postgres://localhost/app") }
    expect_raises(ArgumentError) { Shomen::Store.new("sqlite3::memory:") }
    expect_raises(ArgumentError) { Shomen::Store.new("sqlite3://") }
    expect_raises(ArgumentError) { Shomen::Store.new("sqlite3://:memory:") }
    expect_raises(ArgumentError) { Shomen::Store.new("sqlite3:///") }
  end

  it "names the file it cannot open" do
    dir = File.tempname("shomen-store-dir")
    Dir.mkdir(dir)
    File.chmod(dir, 0o555)
    path = File.join(dir, "shomen.sqlite3")
    begin
      expect_raises(DB::ConnectionRefused, path) { Shomen::Store.new("sqlite3://#{path}") }
    ensure
      File.chmod(dir, 0o755)
      FileUtils.rm_rf(dir)
    end
  end

  it "closes the database when the events table cannot be created" do
    path = File.tempname("shomen-store", ".sqlite3")
    begin
      DB.open("sqlite3://#{path}") do |db|
        db.exec("CREATE TABLE other (x TEXT)")
        db.exec("CREATE INDEX events ON other (x)")
      end
      before = Dir.children("/dev/fd").size
      expect_raises(SQLite3::Exception, "already an index named events") { Shomen::Store.new("sqlite3://#{path}") }
      Dir.children("/dev/fd").size.should eq(before)
    ensure
      remove_database(path)
    end
  end
end
