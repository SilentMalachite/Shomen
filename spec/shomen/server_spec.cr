require "../spec_helper"
require "http/client"

def call_server_raw(method : String, path : String) : String
  io = IO::Memory.new
  request = HTTP::Request.new(method, path)
  response = HTTP::Server::Response.new(io)
  context = HTTP::Server::Context.new(request, response)
  Shomen::Server.new.call(context)
  response.close
  io.to_s
end

def call_server(method : String, path : String) : HTTP::Client::Response
  HTTP::Client::Response.from_io(IO::Memory.new(call_server_raw(method, path)))
end

def assert_security_headers(response)
  response.headers["X-Content-Type-Options"].should eq("nosniff")
  response.headers["Referrer-Policy"].should eq("no-referrer")
  response.headers["X-Frame-Options"].should eq("DENY")
  response.headers["Content-Security-Policy"].should eq(
    "default-src 'self'; base-uri 'none'; form-action 'self'; frame-ancestors 'none'; object-src 'none'"
  )
end

# Stands in for a client socket, which HTTP::Server leaves buffered
# (sync = false): bytes reach the wire only on a flush or a large write.
private class BufferedWire < IO
  include IO::Buffered

  getter wire = IO::Memory.new

  private def unbuffered_read(slice : Bytes) : Int32
    raise "nothing to read from BufferedWire"
  end

  private def unbuffered_write(slice : Bytes) : Nil
    @wire.write(slice)
  end

  private def unbuffered_flush : Nil
  end

  private def unbuffered_close : Nil
  end

  private def unbuffered_rewind : Nil
  end
end

# What reached the wire when call returned. HTTP::Server closes and flushes
# the response only after that, when the request no longer counts as busy.
private def call_over_wire(method : String, path : String) : String
  io = BufferedWire.new
  response = HTTP::Server::Response.new(io)
  Shomen::Server.new.call(HTTP::Server::Context.new(HTTP::Request.new(method, path), response))
  io.wire.to_s
end

describe Shomen::Server do
  it "returns 200 HTML for a matched route" do
    response = call_server("GET", "/phase1/home")
    response.status_code.should eq(200)
    response.headers["Content-Type"].should eq("text/html; charset=utf-8")
    response.body.should contain("<h1>Hello</h1>")
    response.body.should contain("<html lang=\"en\">")
    assert_security_headers(response)
  end

  it "returns 404 HTML for an unknown path" do
    response = call_server("GET", "/phase1/missing")
    response.status_code.should eq(404)
    response.headers["Content-Type"].should eq("text/html; charset=utf-8")
    response.body.should contain("<title>Not found</title>")
    response.body.should_not contain("{")
    assert_security_headers(response)
  end

  it "returns 404 HTML when the route raises NotFound" do
    response = call_server("GET", "/phase1/gone")
    response.status_code.should eq(404)
    response.body.should contain("<title>Not found</title>")
  end

  it "returns 400 HTML when path input is invalid" do
    response = call_server("GET", "/phase1/bad/abc")
    response.status_code.should eq(400)
    response.body.should contain("<title>Bad input</title>")
    response.body.should contain("invalid id")
    assert_security_headers(response)
  end

  it "returns 500 HTML and escapes the exception message" do
    response = call_server("GET", "/phase1/boom")
    response.status_code.should eq(500)
    response.body.should contain("<title>Error</title>")
    response.body.should contain("boom &lt;script&gt;")
    response.body.should_not contain("<script>")
    assert_security_headers(response)
  end

  it "logs an unhandled exception outside production too" do
    Log.capture("shomen") do |logs|
      call_server("GET", "/phase1/boom").status_code.should eq(500)
      logs.check(:error, "unhandled exception")
      logs.entry.exception.try(&.message).should eq("boom <script>")
    end
  end

  it "keeps a redirect location and adds security headers" do
    response = call_server("GET", "/phase1/redirect")
    response.status_code.should eq(303)
    response.headers["Location"].should eq("/phase1/home")
    assert_security_headers(response)
  end

  it "omits the message body for a HEAD route" do
    raw = call_server_raw("HEAD", "/phase1/head")
    response = HTTP::Client::Response.from_io(IO::Memory.new(raw), ignore_body: true)
    response.status_code.should eq(200)
    raw.split("\r\n\r\n", 2)[1].should eq("")
    response.headers["Content-Length"].should eq("<h1>Hello</h1>".bytesize.to_s)
    response.headers["Content-Type"].should eq("text/html; charset=utf-8")
    assert_security_headers(response)
  end

  it "omits the message body for HEAD to an unknown path" do
    get_response = call_server("GET", "/phase1/missing")
    raw = call_server_raw("HEAD", "/phase1/missing")
    response = HTTP::Client::Response.from_io(IO::Memory.new(raw), ignore_body: true)
    response.status_code.should eq(404)
    raw.split("\r\n\r\n", 2)[1].should eq("")
    response.headers["Content-Length"].should eq(get_response.body.bytesize.to_s)
    assert_security_headers(response)
  end

  it "sends each Set-Cookie value on its own header" do
    response = call_server("GET", "/phase1/cookies")
    response.status_code.should eq(200)
    cookies = response.headers.get("Set-Cookie")
    cookies[0, 2].should eq(["a=1", "b=2"])
    cookies[2].should start_with("shomen_session=")
    assert_security_headers(response)
  end

  it "keeps a Content-Security-Policy the route set" do
    response = call_server("GET", "/phase6/csp/own")
    response.headers.get("Content-Security-Policy").should eq([CSPRoutes::Own::POLICY])
    response.headers["X-Frame-Options"].should eq("DENY")
  end

  it "answers with Connection: close once it drains" do
    server = Shomen::Server.new
    call_with(server, "GET", "/phase1/home").headers["Connection"]?.should be_nil
    server.connections.drain
    call_with(server, "GET", "/phase1/home").headers["Connection"].should eq("close")
  end

  it "puts the whole response on the wire before the request stops being busy" do
    response = HTTP::Client::Response.from_io(IO::Memory.new(call_over_wire("GET", "/phase1/home")))
    response.status_code.should eq(200)
    response.body.bytesize.should eq(response.headers["Content-Length"].to_i)
    response.body.should contain("<h1>Hello</h1>")
  end

  it "puts the headers of a HEAD response on the wire before the request stops being busy" do
    raw = call_over_wire("HEAD", "/phase1/head")
    raw.should start_with("HTTP/1.1 200 OK\r\n")
    raw.should end_with("\r\n\r\n")
    raw.should contain("Content-Length: ")
  end
end
