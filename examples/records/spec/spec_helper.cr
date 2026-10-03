require "spec"
require "http/client"
require "db"
require "pg"
require "random/secure"
require "uri"
ENV["SHOMEN_SPEC"] = "1"
ENV["SHOMEN_SECRET"] = "spec-secret"

# The suite runs on a new SQLite file, or, when RECORDS_SPEC_POSTGRES names
# a Postgres server whose user may create databases, on a new database
# there (docs/decisions/20261003-phase8-scale-out.md).
module RecordsSpec
  ADMIN = ENV["RECORDS_SPEC_POSTGRES"]?.presence
  NAME  = "records_spec_#{Random::Secure.hex(8)}"
  FILE  = File.tempname("records", ".sqlite3")

  def self.database_url : String
    if admin = ADMIN
      DB.open(admin) { |db| db.exec("CREATE DATABASE #{NAME}") }
      uri = URI.parse(admin)
      uri.path = "/#{NAME}"
      uri.to_s
    else
      "sqlite3://#{FILE}"
    end
  end

  def self.drop : Nil
    if admin = ADMIN
      DB.open(admin) { |db| db.exec("DROP DATABASE IF EXISTS #{NAME} WITH (FORCE)") }
    else
      [FILE, "#{FILE}-wal", "#{FILE}-shm"].each do |file|
        File.delete(file) if File.exists?(file)
      end
    end
  end
end

ENV["RECORDS_DATABASE_URL"] = RecordsSpec.database_url
require "../src/records"

# The ledger runs for the whole suite, as it does beside the server.
Records::LEDGER.start

Spec.after_suite do
  Records::LEDGER.stop
  Records::STORE.close
  RecordsSpec.drop
end

# A browser without JavaScript: it sends back the cookies the server set,
# so the CSRF token and remember carry from one request to the next.
class Visitor
  getter cookies = HTTP::Cookies.new

  def initialize(@server : Shomen::Server = Shomen::Server.new)
  end

  def get(path : String, headers : HTTP::Headers = HTTP::Headers.new) : HTTP::Client::Response
    request("GET", path, headers, nil)
  end

  # Posts a urlencoded form, with Shomen-Target as shomen.js sends it when
  # target is given.
  def post(path : String, form : Hash(String, String), target : String? = nil) : HTTP::Client::Response
    headers = HTTP::Headers{"Content-Type" => "application/x-www-form-urlencoded"}
    headers["Shomen-Target"] = target if target
    request("POST", path, headers, URI::Params.encode(form))
  end

  def self.token(body : String) : String
    match = body.match(/name="_csrf" value="([^"]+)"/) || raise "no _csrf field in #{body}"
    match[1]
  end

  def self.version(body : String) : String
    match = body.match(/name="version" value="(\d+)"/) || raise "no version field in #{body}"
    match[1]
  end

  private def request(method : String, path : String, headers : HTTP::Headers, body : String?) : HTTP::Client::Response
    @cookies.add_request_headers(headers)
    io = IO::Memory.new
    response = HTTP::Server::Response.new(io)
    @server.call(HTTP::Server::Context.new(HTTP::Request.new(method, path, headers, body), response))
    response.close
    result = HTTP::Client::Response.from_io(IO::Memory.new(io.to_s))
    result.cookies.each { |cookie| @cookies << cookie }
    result
  end
end

# Opens the registration form and sends it.
def register(visitor : Visitor, tag : String, name : String) : HTTP::Client::Response
  page = visitor.get(Items::New.path)
  visitor.post(Items::Create.path, {"_csrf" => Visitor.token(page.body), "tag" => tag, "name" => name})
end

def events_of(tag : String) : Array(Shomen::Recorded)
  Records::STORE.read(after: 0_i64, limit: 10_000).select { |recorded| recorded.stream == Items.stream(tag) }
end

# Opens the item page and sends its lend form.
def lend(visitor : Visitor, tag : String, borrower : String, target : String? = nil) : HTTP::Client::Response
  page = visitor.get(Items::Show.path(tag: tag)).body
  form = {"_csrf" => Visitor.token(page), "version" => Visitor.version(page), "borrower" => borrower}
  visitor.post(Items::Lend.path(tag: tag), form, target)
end

# Opens the item page and sends its return form.
def give_back(visitor : Visitor, tag : String, target : String? = nil) : HTTP::Client::Response
  page = visitor.get(Items::Show.path(tag: tag)).body
  form = {"_csrf" => Visitor.token(page), "version" => Visitor.version(page)}
  visitor.post(Items::Return.path(tag: tag), form, target)
end
