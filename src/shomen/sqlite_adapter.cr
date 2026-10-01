require "uri"
require "db"
require "sqlite3"
require "./store_adapter"

# One SQLite file. Appends, reads, and close in a process take one
# fiber-aware lock per file, and appends then BEGIN IMMEDIATE; other
# processes wait through the busy timeout.
class Shomen::SQLiteAdapter < Shomen::StoreAdapter
  BUSY_TIMEOUT_MS = 5000

  SCHEMA = <<-SQL
    CREATE TABLE IF NOT EXISTS events (
      id      INTEGER PRIMARY KEY,
      stream  TEXT    NOT NULL,
      version INTEGER NOT NULL,
      type    TEXT    NOT NULL,
      payload TEXT    NOT NULL,
      at      TEXT    NOT NULL,
      UNIQUE (stream, version)
    )
    SQL

  SELECT_VERSION = "SELECT COALESCE(MAX(version), 0) FROM events WHERE stream = ?"
  INSERT         = "INSERT INTO events (stream, version, type, payload, at) VALUES (?, ?, ?, ?, ?)"
  SELECT_AFTER   = "SELECT id, stream, version, type, payload FROM events WHERE id > ? ORDER BY id LIMIT ?"
  SELECT_LAST    = "SELECT COALESCE(MAX(id), 0) FROM events"

  @@locks = {} of String => Mutex
  @@locks_lock = Mutex.new

  getter key : String
  @db : DB::Database
  @lock : Mutex

  def initialize(uri : URI)
    filename = SQLite3::Connection.filename(uri)
    if filename.empty? || filename == ":memory:" || Dir.exists?(filename)
      raise ArgumentError.new("store URL must name a file")
    end
    Dir.mkdir_p(File.dirname(filename))
    params = uri.query_params
    # Without the cache every statement is a new one that nothing finalizes,
    # so close fails and a failed statement cannot be reset.
    if params.fetch("prepared_statements_cache", "true") != "true"
      raise ArgumentError.new("store URL must not set prepared_statements_cache")
    end
    params["journal_mode"] = "wal" unless params.has_key?("journal_mode")
    params["busy_timeout"] = BUSY_TIMEOUT_MS.to_s unless params.has_key?("busy_timeout")
    uri.query_params = params
    @db = begin
      DB.open(uri.to_s)
    rescue ex : DB::ConnectionRefused
      raise DB::ConnectionRefused.new("cannot open #{filename}", cause: ex)
    end
    begin
      @db.using_connection do |connection|
        connection.exec(SCHEMA)
      rescue ex
        reset(connection, SCHEMA)
        raise ex
      end
    rescue ex
      @db.close
      raise ex
    end
    real = File.realpath(filename)
    @key = "sqlite3://#{real}"
    @lock = @@locks_lock.synchronize { @@locks[real] ||= Mutex.new }
  end

  def append(stream : String, expected_version : Int64, rows : Array(Row)) : Int64
    @lock.synchronize do
      @db.using_connection do |connection|
        begin
          connection.exec("BEGIN IMMEDIATE")
        rescue ex
          reset(connection, "BEGIN IMMEDIATE")
          raise ex
        end
        begin
          id = insert(connection, stream, expected_version, rows)
          connection.exec("COMMIT")
          id
        rescue ex
          rollback(connection)
          raise ex
        end
      end
    end
  end

  def read(after : Int64, limit : Int32) : Array(Stored)
    @lock.synchronize do
      @db.query_all(SELECT_AFTER, after, limit, as: {Int64, String, Int64, String, String})
    end
  end

  def last_id : Int64
    @lock.synchronize { @db.scalar(SELECT_LAST).as(Int64) }
  end

  # Waits for an append or read in progress, which would otherwise use a
  # statement that close has finalized.
  def close : Nil
    @lock.synchronize { @db.close }
  end

  # SQLite may already have rolled back (a full disk, a trigger), so a
  # failed ROLLBACK must not hide the error that caused it.
  private def rollback(connection : DB::Connection) : Nil
    connection.exec("ROLLBACK")
  rescue
    reset(connection, "ROLLBACK")
  ensure
    [SELECT_VERSION, INSERT, "COMMIT"].each { |sql| reset(connection, sql) }
  end

  # A statement that failed keeps its error until it is reset, and
  # crystal-sqlite3 raises that error again when the connection closes.
  private def reset(connection : DB::Connection, sql : String) : Nil
    LibSQLite3.reset(connection.fetch_or_build_prepared_statement(sql).as(SQLite3::Statement))
  end

  private def insert(connection : DB::Connection, stream : String, expected_version : Int64, rows : Array(Row)) : Int64
    check_version(stream, connection.scalar(SELECT_VERSION, stream).as(Int64), expected_version)
    last_id = 0_i64
    rows.each_with_index(1) do |row, offset|
      type, payload, at = row
      last_id = connection.exec(INSERT, stream, expected_version + offset, type, payload, at).last_insert_id
    end
    last_id
  end
end
