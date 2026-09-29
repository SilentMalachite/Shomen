require "./spec_helper"
require "http/client"

private def request_with(server : Shomen::Server, method : String, path : String, target : String? = nil, cookie : String? = nil, body : String? = nil) : HTTP::Client::Response
  headers = HTTP::Headers.new
  headers["Shomen-Target"] = target if target
  headers["Cookie"] = cookie if cookie
  headers["Content-Type"] = "application/x-www-form-urlencoded" if body
  io = IO::Memory.new
  response = HTTP::Server::Response.new(io)
  server.call(HTTP::Server::Context.new(HTTP::Request.new(method, path, headers, body), response))
  response.close
  HTTP::Client::Response.from_io(IO::Memory.new(io.to_s))
end

private def open_page(server : Shomen::Server) : {String, String}
  response = request_with(server, "GET", "/greeting")
  cookie = response.headers["Set-Cookie"].split(';').first
  token = response.body.match(/name="_csrf" value="([^"]+)"/).not_nil![1]
  {cookie, token}
end

describe "Greeting with shomen.js" do
  it "loads the script and marks the change link" do
    response = request_with(Shomen::Server.new, "GET", "/greeting/Ada")
    response.body.should contain("<script src=\"/shomen.js\" defer></script>")
    response.body.should contain("<div id=\"greeting-form\"><a href=\"/greeting\" data-shomen-get=\"greeting-form\">Change</a></div>")
  end

  it "wraps the form of the page in the element the script replaces" do
    response = request_with(Shomen::Server.new, "GET", "/greeting")
    response.body.should start_with("<!DOCTYPE html>")
    response.body.should contain("<script src=\"/shomen.js\" defer></script>")
    response.body.should contain("<h1>Greeting</h1><div id=\"greeting-form\"><form action=\"/greeting\" method=\"post\" data-shomen-post=\"greeting-form\">")
  end

  it "answers the change link with only the form" do
    response = request_with(Shomen::Server.new, "GET", "/greeting", target: "greeting-form")
    response.status_code.should eq(200)
    response.body.should start_with("<div id=\"greeting-form\"><form action=\"/greeting\" method=\"post\" data-shomen-post=\"greeting-form\">")
    response.body.should contain("<button type=\"submit\" id=\"greeting-save\">Save</button>")
    response.body.should_not contain("<html")
  end

  it "redisplays only the form with 422" do
    server = Shomen::Server.new
    cookie, token = open_page(server)
    body = URI::Params.encode({"_csrf" => token, "name" => "<"})
    response = request_with(server, "POST", "/greeting", "greeting-form", cookie, body)
    response.status_code.should eq(422)
    response.body.should start_with("<div id=\"greeting-form\"><p role=\"alert\">Name must be at least 2 characters</p>")
    response.body.should contain("value=\"&lt;\"")
    response.body.should_not contain("<html")
  end

  it "redirects a valid name with or without the script" do
    server = Shomen::Server.new
    cookie, token = open_page(server)
    body = URI::Params.encode({"_csrf" => token, "name" => "Ada"})
    response = request_with(server, "POST", "/greeting", "greeting-form", cookie, body)
    response.status_code.should eq(303)
    response.headers["Location"].should eq("/greeting/Ada")
  end

  it "serves shomen.js" do
    response = request_with(Shomen::Server.new, "GET", "/shomen.js")
    response.status_code.should eq(200)
    response.headers["Content-Type"].should eq("text/javascript; charset=utf-8")
  end
end
