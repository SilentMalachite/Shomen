require "uri"
require "db"
require "pg"
require "./store_adapter"

# A Postgres database. Every append, and the creation of the events table,
# first takes one transaction-scoped advisory lock and commits right away,
# so ids become visible in increasing order
# (docs/decisions/20260929-scale-event-order.md,
# docs/decisions/20260929-phase6-postgres-adapter.md).
class Shomen::PostgresAdapter < Shomen::StoreAdapter
  # "shomen" in ASCII.
  LOCK_KEY  = 0x73686f6d656e_i64
  POOL_SIZE = "10"
  # What the driver connects to when the URL names no port.
  DEFAULT_PORT = 5432

  SCHEMA = <<-SQL
    CREATE TABLE IF NOT EXISTS events (
      id      BIGINT GENERATED ALWAYS AS IDENTITY (CACHE 1) PRIMARY KEY,
      stream  TEXT   NOT NULL,
      version BIGINT NOT NULL,
      type    TEXT   NOT NULL,
      payload TEXT   NOT NULL,
      at      TEXT   NOT NULL,
      UNIQUE (stream, version)
    )
    SQL

  LOCK           = "SELECT pg_advisory_xact_lock($1)"
  SELECT_VERSION = "SELECT COALESCE(MAX(version), 0) FROM events WHERE stream = $1"
  INSERT         = "INSERT INTO events (stream, version, type, payload, at) VALUES ($1, $2, $3, $4, $5) RETURNING id"
  SELECT_AFTER   = "SELECT id, stream, version, type, payload FROM events WHERE id > $1 ORDER BY id LIMIT $2"

  getter key : String
  @db : DB::Database

  def initialize(uri : URI)
    database = uri.path.lchop('/')
    raise ArgumentError.new("store URL must name a database") if database.empty?
    @key = "postgres://#{uri.host}:#{uri.port || DEFAULT_PORT}/#{database}"
    params = uri.query_params
    params["max_pool_size"] = POOL_SIZE unless params.has_key?("max_pool_size")
    params["max_idle_pool_size"] = params["max_pool_size"] unless params.has_key?("max_idle_pool_size")
    uri.query_params = params
    @db = DB.open(uri.to_s)
    begin
      locked { |connection| connection.exec(SCHEMA) }
    rescue ex
      @db.close
      raise ex
    end
  end

  def append(stream : String, expected_version : Int64, rows : Array(Row)) : Int64
    locked do |connection|
      check_version(stream, connection.scalar(SELECT_VERSION, stream).as(Int64), expected_version)
      last_id = 0_i64
      rows.each_with_index(1) do |row, offset|
        type, payload, at = row
        last_id = connection.scalar(INSERT, stream, expected_version + offset, type, payload, at).as(Int64)
      end
      last_id
    end
  end

  def read(after : Int64, limit : Int32) : Array(Stored)
    @db.query_all(SELECT_AFTER, after, limit, as: {Int64, String, Int64, String, String})
  end

  def close : Nil
    @db.close
  end

  # Runs the block in a transaction that holds the lock, and commits as
  # soon as the block returns.
  private def locked(& : DB::Connection -> T) : T forall T
    @db.using_connection do |connection|
      connection.exec("BEGIN")
      begin
        connection.exec(LOCK, LOCK_KEY)
        result = yield connection
        connection.exec("COMMIT")
        result
      rescue ex
        rollback(connection)
        raise ex
      end
    end
  end

  # A connection that broke cannot roll back, and the error that broke it
  # matters more.
  private def rollback(connection : DB::Connection) : Nil
    connection.exec("ROLLBACK")
  rescue
  end
end
