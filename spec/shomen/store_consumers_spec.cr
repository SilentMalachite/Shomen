require "../spec_helper"

private def notes_table(connection : DB::Connection) : Nil
  connection.exec("CREATE TABLE IF NOT EXISTS spec_notes (event_id BIGINT NOT NULL, text TEXT NOT NULL, max_before BIGINT NOT NULL)")
end

private def count(store : Shomen::Store, table : String) : Int64
  store.using_connection { |connection| connection.scalar("SELECT COUNT(*) FROM #{table}").as(Int64) }
end

describe "the consumers of a store" do
  store_it "start with an empty consumers table" do |store|
    count(store, "consumers").should eq(0_i64)
  end

  store_it "register a consumer at checkpoint 0 with its tables, once" do |store|
    2.times { store.register("spec_notes") { |connection| notes_table(connection) } }
    store.checkpoint("spec_notes").should eq(0_i64)
    count(store, "consumers").should eq(1_i64)
    count(store, "spec_notes").should eq(0_i64)
  end

  store_it "have checkpoint 0 for a name the store does not know" do |store|
    store.checkpoint("nobody").should eq(0_i64)
  end

  store_it "keep neither the tables nor the row when creating the tables fails" do |store|
    expect_raises(Exception, "no tables") do
      store.register("spec_notes") do |connection|
        notes_table(connection)
        raise "no tables"
      end
    end
    count(store, "consumers").should eq(0_i64)
    expect_raises(Exception) { count(store, "spec_notes") }
  end

  store_it "reject an empty name" do |store|
    expect_raises(ArgumentError, "consumer name must not be empty") do
      store.register("") { |_| }
    end
  end

  store_it "let the store close after a statement failed on a lent connection" do |_, url|
    store = Shomen::Store.new(url)
    store.using_connection do |connection|
      connection.exec("CREATE TABLE IF NOT EXISTS spec_unique (a TEXT UNIQUE)")
      connection.exec("INSERT INTO spec_unique (a) VALUES ($1)", "x")
    end
    expect_raises(Exception) do
      store.using_connection { |connection| connection.exec("INSERT INTO spec_unique (a) VALUES ($1)", "x") }
    end
    store.close
  end

  store_it "lets the store close after the block rescued its own failed statement" do |_, url|
    store = Shomen::Store.new(url)
    store.using_connection do |connection|
      connection.exec("CREATE TABLE IF NOT EXISTS spec_unique_rescued (a TEXT UNIQUE)")
      connection.exec("INSERT INTO spec_unique_rescued (a) VALUES ($1)", "x")
      begin
        connection.exec("INSERT INTO spec_unique_rescued (a) VALUES ($1)", "x")
      rescue
      end
    end
    store.close
  end
end
