require "uri"
require "random/secure"

# Postgres specs run when SHOMEN_SPEC_POSTGRES is a server URL whose user
# may create databases. Each example gets a database of its own and drops
# it afterwards (docs/decisions/20260929-phase6-postgres-spec.md).
module PostgresSpec
  def self.admin_url : String?
    ENV["SHOMEN_SPEC_POSTGRES"]?.presence
  end

  def self.with_database(& : String ->) : Nil
    admin = admin_url || raise "SHOMEN_SPEC_POSTGRES is not set"
    name = "shomen_spec_#{Random::Secure.hex(8)}"
    DB.open(admin) { |db| db.exec("CREATE DATABASE #{name}") }
    uri = URI.parse(admin)
    uri.path = "/#{name}"
    begin
      yield uri.to_s
    ensure
      DB.open(admin) { |db| db.exec("DROP DATABASE IF EXISTS #{name} WITH (FORCE)") }
    end
  end

  # Makes the table in to hold the rows of the one in from, as a replica
  # that caught up to this moment would; events keep their ids, and only
  # those up to upto when given
  # (docs/decisions/20261001-phase7-replica-spec.md).
  def self.copy(from : String, to : String, table : String, upto : Int64? = nil) : Nil
    rows = DB.open(from) do |db|
      if upto
        db.query_all("SELECT row_to_json(t)::text FROM #{table} t WHERE id <= $1", upto, as: String)
      else
        db.query_all("SELECT row_to_json(t)::text FROM #{table} t", as: String)
      end
    end
    overriding = table == "events" ? "OVERRIDING SYSTEM VALUE" : ""
    DB.open(to) do |db|
      db.transaction do |transaction|
        connection = transaction.connection
        connection.exec("DELETE FROM #{table}")
        rows.each do |row|
          connection.exec("INSERT INTO #{table} #{overriding} SELECT * FROM json_populate_record(NULL::#{table}, $1::json)", row)
        end
      end
    end
  end

  # A primary database and a replica database with the store's tables,
  # which the spec fills with copy.
  def self.with_replica(& : String, String ->) : Nil
    with_database do |primary|
      with_database do |replica|
        Shomen::Store.new(replica).close
        yield primary, replica
      end
    end
  end

  # The pids of the connections in db's database that listen for appends
  # (docs/decisions/20261001-phase7-notify-channel.md).
  def self.listeners(db : DB::Database) : Array(Int32)
    db.query_all(
      "SELECT pid FROM pg_stat_activity WHERE datname = current_database() AND application_name LIKE 'shomen-listen-%' AND query LIKE 'LISTEN%'",
      as: Int32,
    )
  end
end

# An example on a new, empty Postgres database; pending without
# SHOMEN_SPEC_POSTGRES.
def postgres_database_it(description : String, file = __FILE__, line = __LINE__, &block : String ->) : Nil
  if PostgresSpec.admin_url
    it(description, file, line) { PostgresSpec.with_database { |url| block.call(url) } }
  else
    pending(description, file, line) { }
  end
end

# An example on a new primary and a replica database that lags until the
# spec copies to it; pending without SHOMEN_SPEC_POSTGRES.
def replica_it(description : String, file = __FILE__, line = __LINE__, &block : String, String ->) : Nil
  if PostgresSpec.admin_url
    it(description, file, line) { PostgresSpec.with_replica { |primary, replica| block.call(primary, replica) } }
  else
    pending(description, file, line) { }
  end
end
