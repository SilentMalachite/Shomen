require "./spec_helper"
require "http/client"

private def request(server : Shomen::Server, method : String, path : String, cookie : String? = nil, body : String? = nil) : HTTP::Client::Response
  headers = HTTP::Headers.new
  headers["Cookie"] = cookie if cookie
  headers["Content-Type"] = "application/x-www-form-urlencoded" if body
  io = IO::Memory.new
  response = HTTP::Server::Response.new(io)
  server.call(HTTP::Server::Context.new(HTTP::Request.new(method, path, headers, body), response))
  response.close
  HTTP::Client::Response.from_io(IO::Memory.new(io.to_s))
end

private def open_form(server : Shomen::Server) : {String, String}
  response = request(server, "GET", "/greeting")
  cookie = response.headers["Set-Cookie"].split(';').first
  token = response.body.match(/name="_csrf" value="([^"]+)"/).not_nil![1]
  {cookie, token}
end

describe Greeting do
  it "shows the form with a label, a csrf field, and a session cookie" do
    response = request(Shomen::Server.new, "GET", "/greeting")
    response.status_code.should eq(200)
    response.body.should contain("<label for=\"name\">Name</label>")
    response.body.should contain("name=\"_csrf\"")
    response.headers["Set-Cookie"].should start_with("shomen_session=")
  end

  it "redisplays the submitted value with 422 when it is too short" do
    server = Shomen::Server.new
    cookie, token = open_form(server)
    body = URI::Params.encode({"_csrf" => token, "name" => "<"})
    response = request(server, "POST", "/greeting", cookie, body)
    response.status_code.should eq(422)
    response.body.should contain("value=\"&lt;\"")
    response.body.should contain("Name must be at least 2 characters")
  end

  it "redirects with 303 to the greeting when the name is valid" do
    server = Shomen::Server.new
    cookie, token = open_form(server)
    body = URI::Params.encode({"_csrf" => token, "name" => " Ada "})
    response = request(server, "POST", "/greeting", cookie, body)
    response.status_code.should eq(303)
    response.headers["Location"].should eq("/greeting/Ada")
  end

  it "shows the saved name escaped" do
    response = request(Shomen::Server.new, "GET", "/greeting/%3Cb%3E")
    response.status_code.should eq(200)
    response.body.should contain("<h1>Hello, &lt;b&gt;</h1>")
    response.body.should contain("href=\"/greeting\"")
  end

  it "redisplays a name with a slash, question mark, or hash with 422" do
    server = Shomen::Server.new
    cookie, token = open_form(server)
    ["a/b", "a?b", "a#b"].each do |name|
      body = URI::Params.encode({"_csrf" => token, "name" => name})
      response = request(server, "POST", "/greeting", cookie, body)
      response.status_code.should eq(422)
      response.body.should contain("Name must not contain /, ?, or #")
    end
  end

  it "redisplays a name of .. with 422" do
    server = Shomen::Server.new
    cookie, token = open_form(server)
    body = URI::Params.encode({"_csrf" => token, "name" => " .. "})
    response = request(server, "POST", "/greeting", cookie, body)
    response.status_code.should eq(422)
    response.body.should contain("Name must not be ..")
  end

  it "rejects a POST without the csrf token" do
    server = Shomen::Server.new
    cookie, _ = open_form(server)
    request(server, "POST", "/greeting", cookie, "name=Ada").status_code.should eq(403)
  end

  it "exposes the declared path" do
    Greeting::Edit.path.should eq("/greeting")
  end
end
