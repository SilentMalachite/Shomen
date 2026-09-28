require "http"
require "http/client"

def call_with(server : Shomen::Server, method : String, path : String, cookie : String? = nil, body : String? = nil, content_type : String = "application/x-www-form-urlencoded") : HTTP::Client::Response
  headers = HTTP::Headers.new
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
