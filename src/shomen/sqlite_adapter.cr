require "uri"
require "db"
require "sqlite3"
require "./store_adapter"

module Shomen
  # crystal-sqlite3 does not bind sqlite3_next_stmt. The library is linked
  # already, so no Link annotation (a second one makes ld warn).
  lib LibSQLite
    fun next_stmt = sqlite3_next_stmt(db : LibSQLite3::SQLite3, stmt : Void*) : Void*
  end
end

# One SQLite file. Appends, reads, and close in a process take one
# fiber-aware lock per file, and appends then BEGIN IMMEDIATE; other
# processes wait through the busy timeout.
class Shomen::SQLiteAdapter < Shomen::StoreAdapter
  BUSY_TIMEOUT_MS = 5000
  # SQLITE_BUSY, the primary result code.
  BUSY = 5
  WAL  = "PRAGMA journal_mode=wal"

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

  CONSUMERS_SCHEMA = <<-SQL
    CREATE TABLE IF NOT EXISTS consumers (
      name       TEXT    PRIMARY KEY,
      checkpoint INTEGER NOT NULL
    )
    SQL

  SELECT_VERSION = "SELECT COALESCE(MAX(version), 0) FROM events WHERE stream = ?"
  INSERT         = "INSERT INTO events (stream, version, type, payload, at) VALUES (?, ?, ?, ?, ?)"
  SELECT_AFTER   = "SELECT id, stream, version, type, payload FROM events WHERE id > ? ORDER BY id LIMIT ?"
  SELECT_LAST    = "SELECT COALESCE(MAX(id), 0) FROM events"

  REGISTER          = "INSERT INTO consumers (name, checkpoint) VALUES (?, 0) ON CONFLICT (name) DO NOTHING"
  SELECT_CHECKPOINT = "SELECT COALESCE(MAX(checkpoint), 0) FROM consumers WHERE name = ?"
  ADVANCE           = "UPDATE consumers SET checkpoint = ? WHERE name = ? AND checkpoint = ?"

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
    # WAL is set once below, not by every connection the URL opens.
    wal = !params.has_key?("journal_mode")
    params["busy_timeout"] = BUSY_TIMEOUT_MS.to_s unless params.has_key?("busy_timeout")
    uri.query_params = params
    @db = begin
      DB.open(uri.to_s)
    rescue ex : DB::ConnectionRefused
      raise DB::ConnectionRefused.new("cannot open #{filename}", cause: ex)
    end
    begin
      @db.using_connection do |connection|
        use_wal(connection, (params["busy_timeout"].to_i? || BUSY_TIMEOUT_MS).milliseconds) if wal
        connection.exec(SCHEMA)
        connection.exec(CONSUMERS_SCHEMA)
      rescue ex
        reset_all(connection)
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

  def register(name : String, & : DB::Connection ->) : Nil
    transaction do |connection|
      yield connection
      connection.exec(REGISTER, name)
      true
    end
  end

  def checkpoint(name : String) : Int64
    @lock.synchronize { @db.scalar(SELECT_CHECKPOINT, name).as(Int64) }
  end

  # Inside the file's lock, so close waits for the read.
  def using_connection(& : DB::Connection ->) : Nil
    @lock.synchronize do
      @db.using_connection do |connection|
        yield connection
      ensure
        reset_all(connection)
      end
    end
  end

  # Runs the side effects outside any transaction, as SQLite's lock covers
  # the whole file, then commits the writes in a short transaction that
  # moves the checkpoint only from the value it read. When another process
  # moved it first, nothing is written, and a failure here no longer
  # matters.
  def consume(name : String, limit : Int32, react : Proc(Stored, Nil), write : Proc(Stored, DB::Connection, Nil)) : Int32
    from = checkpoint(name)
    rows = read(from, limit)
    error = nil
    reacted = 0
    rows.each do |row|
      begin
        react.call(row)
      rescue ex
        error = ex
        break
      end
      reacted += 1
    end
    applied = 0
    if reacted > 0
      committed = transaction do |connection|
        next false unless connection.scalar(SELECT_CHECKPOINT, name).as(Int64) == from
        applied, last, failure = each_in_savepoint(connection, rows[0, reacted]) { |row| write.call(row, connection) }
        if failure
          reset_all(connection)
          error = failure
        end
        applied == 0 || connection.exec(ADVANCE, last, name, from).rows_affected == 1
      end
      return 0 unless committed
    end
    raise error if error
    applied
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

  # Switches the file to WAL; the mode stays with the file. When two
  # processes switch a new file at once, SQLite answers one of them
  # SQLITE_BUSY without waiting, as waiting could deadlock. That one tries
  # again until the busy timeout
  # (docs/decisions/20261003-sqlite-concurrent-open.md).
  private def use_wal(connection : DB::Connection, timeout : Time::Span) : Nil
    deadline = Time.instant + timeout
    loop do
      begin
        connection.scalar(WAL)
        return
      rescue ex : SQLite3::Exception
        reset(connection, WAL)
        raise ex unless ex.code == BUSY && Time.instant < deadline
      end
      sleep 10.milliseconds
    end
  end

  # A statement that failed keeps its error until it is reset, and
  # crystal-sqlite3 raises that error again when the connection closes.
  private def reset(connection : DB::Connection, sql : String) : Nil
    LibSQLite3.reset(connection.fetch_or_build_prepared_statement(sql).as(SQLite3::Statement))
  end

  # BEGIN IMMEDIATE under the file's lock. Commits when the block returns
  # true; rolls back when it returns false or raises.
  private def transaction(& : DB::Connection -> Bool) : Bool
    @lock.synchronize do
      @db.using_connection do |connection|
        begin
          connection.exec("BEGIN IMMEDIATE")
        rescue ex
          reset_all(connection)
          raise ex
        end
        begin
          commit = yield connection
          connection.exec(commit ? "COMMIT" : "ROLLBACK")
          commit
        rescue ex
          begin
            connection.exec("ROLLBACK")
          rescue
          end
          raise ex
        ensure
          reset_all(connection)
        end
      end
    end
  end

  # Resets every statement of the connection, as a consumer runs SQL that
  # Shomen did not write, and a failed one the app rescued would raise again
  # on close (docs/decisions/20261001-phase7-consumer-batch.md).
  private def reset_all(connection : DB::Connection) : Nil
    handle = connection.as(SQLite3::Connection).to_unsafe
    statement = Shomen::LibSQLite.next_stmt(handle, Pointer(Void).null)
    until statement.null?
      LibSQLite3.reset(statement.as(LibSQLite3::Statement))
      statement = Shomen::LibSQLite.next_stmt(handle, statement)
    end
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
