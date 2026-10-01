require "../spec_helper"

private def wait_for_checkpoint(url : String, id : Int64) : Nil
  DB.open(url) do |db|
    wait_until(30.seconds) do
      db.query_one?("SELECT checkpoint FROM consumers WHERE name = 'spec_notes'", as: Int64) == id
    end
  end
end

# Each event of 1 to count has exactly one row, and each row was written
# when the rows of every earlier event were in the table and no later one.
private def check_applied(url : String, count : Int32) : Nil
  DB.open(url) do |db|
    rows = db.query_all("SELECT event_id, max_before FROM spec_notes ORDER BY event_id", as: {Int64, Int64})
    rows.map(&.[0]).should eq((1_i64..count.to_i64).to_a)
    rows.map(&.[1]).should eq((0_i64...count.to_i64).to_a)
  end
end

private def texts(prefix : String, count : Int32) : Array(Shomen::Event)
  noted(Array.new(count) { |index| "#{prefix} #{index}" })
end

private def two_processes(url : String) : Nil
  Workers.binary(ConsumerProcess::SOURCE)
  store = Shomen::Store.new(url)
  begin
    store.append("before", 0_i64, texts("before", 250))
    with_consumer_process(url) do |first|
      with_consumer_process(url) do |second|
        store.append("after", 0_i64, texts("after", 50))
        wait_for_checkpoint(url, 300_i64)
        first.finish
        second.finish
      end
    end
    check_applied(url, 300)
  ensure
    store.close
  end
end

private def killed_during_batch(url : String) : Nil
  Workers.binary(ConsumerProcess::SOURCE)
  store = Shomen::Store.new(url)
  begin
    store.append("notes", 0_i64, noted((1..10).map { |index| index == 5 ? "stall" : "note #{index}" }))
    with_consumer_process(url, "stall") do |stalling|
      stalling.expect("stalled")
      with_consumer_process(url) do |other|
        stalling.kill
        wait_for_checkpoint(url, 10_i64)
        other.finish
      end
    end
    check_applied(url, 10)
  ensure
    store.close
  end
end

private def with_sqlite_url(& : String ->) : Nil
  path = File.tempname("shomen-consumers", ".sqlite3")
  begin
    yield "sqlite3://#{path}"
  ensure
    remove_database(path)
  end
end

describe "one consumer in two processes" do
  it "applies each event's writes once, in id order, on one SQLite file" do
    with_sqlite_url { |url| two_processes(url) }
  end

  postgres_database_it "applies each event's writes once, in id order, on one Postgres database" do |url|
    two_processes(url)
  end

  it "continues from the stored checkpoint after the other process is killed during a batch, on SQLite" do
    with_sqlite_url { |url| killed_during_batch(url) }
  end

  postgres_database_it "continues from the stored checkpoint after the other process is killed during a batch, on Postgres" do |url|
    killed_during_batch(url)
  end
end
