require "uri"
require "db"
require "sqlite3"
require "./event"
require "./recorded"
require "./conflict"

# Append-only event log in one SQLite file. Appends, reads, and close in a
# process take one fiber-aware lock per file, and appends then BEGIN
# IMMEDIATE; other processes wait through the busy timeout.
class Shomen::Store
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

  @@locks = {} of String => Mutex
  @@locks_lock = Mutex.new

  @db : DB::Database
  @lock : Mutex

  def initialize(url : String)
    uri = begin
      URI.parse(url)
    rescue ex : URI::Error
      raise ArgumentError.new("store URL is not valid: #{ex.message}")
    end
    raise ArgumentError.new("store URL must use sqlite3, got #{uri.scheme.inspect}") unless uri.scheme == "sqlite3"
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
    @lock = @@locks_lock.synchronize { @@locks[real] ||= Mutex.new }
  end

  def append(stream : String, expected_version : Int64, events : Array(Shomen::Event)) : Nil
    raise ArgumentError.new("stream must not be empty") if stream.empty?
    raise ArgumentError.new("expected_version must not be negative") if expected_version < 0
    return if events.empty?
    events.each do |event|
      raise ArgumentError.new("#{event.event_type} at must be UTC, got #{event.at}") unless event.at.utc?
    end
    rows = events.map { |event| {event.event_type, event.to_json, event.at.to_rfc3339} }
    @lock.synchronize do
      @db.using_connection do |connection|
        begin
          connection.exec("BEGIN IMMEDIATE")
        rescue ex
          reset(connection, "BEGIN IMMEDIATE")
          raise ex
        end
        begin
          insert(connection, stream, expected_version, rows)
          connection.exec("COMMIT")
        rescue ex
          rollback(connection)
          raise ex
        end
      end
    end
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

  private def insert(connection : DB::Connection, stream : String, expected_version : Int64, rows : Array({String, String, String})) : Nil
    current = connection.scalar(SELECT_VERSION, stream).as(Int64)
    unless current == expected_version
      raise Shomen::Conflict.new("stream #{stream} is at version #{current}, expected #{expected_version}")
    end
    rows.each_with_index(1) do |row, offset|
      type, payload, at = row
      connection.exec(INSERT, stream, expected_version + offset, type, payload, at)
    end
  end

  def read(after : Int64, limit : Int32 = 500) : Array(Shomen::Recorded)
    rows = @lock.synchronize do
      @db.query_all(
        "SELECT id, stream, version, type, payload FROM events WHERE id > ? ORDER BY id LIMIT ?",
        after, limit,
        as: {Int64, String, Int64, String, String},
      )
    end
    rows.map do |row|
      id, stream, version, type, payload = row
      Shomen::Recorded.new(id, stream, version, Shomen::Event.decode(type, payload))
    end
  end

  # Waits for an append or read in progress, which would otherwise use a
  # statement that close has finalized.
  def close : Nil
    @lock.synchronize { @db.close }
  end
end
