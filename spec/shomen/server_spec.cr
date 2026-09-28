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
    response.headers.get("Set-Cookie").should eq(["a=1", "b=2"])
    assert_security_headers(response)
  end
end
