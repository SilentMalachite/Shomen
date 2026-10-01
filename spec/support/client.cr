require "http"
require "http/client"

def call_with(server : Shomen::Server, method : String, path : String, cookie : String? = nil, body : String? = nil, content_type : String = "application/x-www-form-urlencoded", headers : HTTP::Headers = HTTP::Headers.new) : HTTP::Client::Response
  headers = headers.dup
  headers["Cookie"] = cookie if cookie
  headers["Content-Type"] = content_type if body
  io = IO::Memory.new
  response = HTTP::Server::Response.new(io)
  server.call(HTTP::Server::Context.new(HTTP::Request.new(method, path, headers, body), response))
  response.close
  HTTP::Client::Response.from_io(IO::Memory.new(io.to_s))
end

def session_cookie(response : HTTP::Client::Response) : String
  header = response.headers.get("Set-Cookie").find(&.starts_with?("shomen_session=")) || raise "no session cookie"
  header.split(';').first
end

# The name=value of the shomen_append cookie the response sets, or nil.
def append_cookie?(response : HTTP::Client::Response) : String?
  response.headers.get?("Set-Cookie").try(&.find(&.starts_with?("shomen_append="))).try(&.split(';').first)
end
