require "uri"
require "db"
require "pg"
require "random/secure"
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
  SELECT_LAST    = "SELECT COALESCE(MAX(id), 0) FROM events"
  # docs/decisions/20261001-phase7-notify-channel.md
  CHANNEL = "shomen_events"
  NOTIFY  = "SELECT pg_notify($1, $2)"

  LISTENER_PREFIX = "shomen-listen-"
  TERMINATE       = "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE application_name = $1 AND pid <> pg_backend_pid()"

  getter key : String
  @db : DB::Database
  @listen_url : String
  @listener_name : String

  def initialize(uri : URI)
    database = uri.path.lchop('/')
    raise ArgumentError.new("store URL must name a database") if database.empty?
    @key = self.class.key(uri)
    @listener_name = LISTENER_PREFIX + Random::Secure.hex(8)
    listen_uri = uri.dup
    listen_params = listen_uri.query_params
    listen_params["application_name"] = @listener_name
    listen_uri.query_params = listen_params
    @listen_url = listen_uri.to_s
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

  # The server and database the driver connects to, as it resolves them
  # from the URL, its query and PGHOST / PGPORT, so every URL for one
  # database shares one append signal.
  def self.key(uri : URI) : String
    info = PQ::ConnInfo.new(uri)
    "postgres://#{info.host}:#{info.port}/#{info.database}"
  end

  # Sends the last id on CHANNEL before COMMIT, so the notification goes
  # out only when the append commits.
  def append(stream : String, expected_version : Int64, rows : Array(Row)) : Int64
    locked do |connection|
      check_version(stream, connection.scalar(SELECT_VERSION, stream).as(Int64), expected_version)
      last_id = 0_i64
      rows.each_with_index(1) do |row, offset|
        type, payload, at = row
        last_id = connection.scalar(INSERT, stream, expected_version + offset, type, payload, at).as(Int64)
      end
      connection.exec(NOTIFY, CHANNEL, last_id.to_s)
      last_id
    end
  end

  def read(after : Int64, limit : Int32) : Array(Stored)
    @db.query_all(SELECT_AFTER, after, limit, as: {Int64, String, Int64, String, String})
  end

  def last_id : Int64
    @db.scalar(SELECT_LAST).as(Int64)
  end

  def notifies? : Bool
    true
  end

  # On a connection outside the pool, named so interrupt_listen can end it
  # (docs/decisions/20261001-phase7-notify-channel.md). A payload that is
  # not an id comes from outside Shomen and is ignored.
  def listen(on_id : Int64 -> Nil) : Nil
    PG.connect_listen(@listen_url, CHANNEL, blocking: true) do |notification|
      if id = notification.payload.to_i64?
        on_id.call(id)
      end
    end
  end

  def interrupt_listen : Nil
    @db.exec(TERMINATE, @listener_name)
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
