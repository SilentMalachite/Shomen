require "shomen"
require "./records/events"
require "./records/ledger"
require "./records/commands"
require "./records/views"
require "./records/routes"

# Where the application keeps its events and tables. Only these variables
# differ between one process on SQLite and many on Postgres
# (docs/decisions/20261003-phase8-records.md).
module Records
  STORE  = Shomen::Store.new(ENV["RECORDS_DATABASE_URL"]? || "sqlite3://./var/records.sqlite3", replica: ENV["RECORDS_REPLICA_URL"]?.presence)
  LEDGER = Items::Ledger.new(STORE)
  CACHE  = Shomen::FragmentCache.new

  # 3000 when RECORDS_PORT is unset. Anything but a port number is an
  # error rather than a port the server would pick.
  def self.port : Int32
    raw = ENV["RECORDS_PORT"]? || return 3000
    port = raw.to_i32?(whitespace: false)
    return port if port && 0 < port <= 65_535
    raise ArgumentError.new("RECORDS_PORT is not a port number: #{raw.inspect}")
  end
end

# The ledger starts before the server and stops after it, before the store
# closes (docs/en/00-INSTRUCTION.md, the consumer section).
unless ENV["SHOMEN_SPEC"]?
  Records::LEDGER.start
  Shomen::Server.start(port: Records.port)
  Records::LEDGER.stop
  Records::STORE.close
end
