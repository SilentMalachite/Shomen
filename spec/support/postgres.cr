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
