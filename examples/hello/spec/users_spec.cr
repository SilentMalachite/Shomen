require "./spec_helper"
require "http/client"

struct UserNoted
  include Shomen::Event
  event_type "spec.user_noted"

  getter at : Time

  def initialize(@at : Time = Time.utc)
  end
end

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

private def open_edit(server : Shomen::Server, id : Int64) : {String, String, String}
  response = request(server, "GET", "/users/#{id}/edit")
  cookie = response.headers["Set-Cookie"].split(';').first
  token = response.body.match(/name="_csrf" value="([^"]+)"/).not_nil![1]
  version = response.body.match(/name="version" value="(\d+)"/).not_nil![1]
  {cookie, token, version}
end

private def post_rename(server : Shomen::Server, id : Int64, cookie : String, token : String, version : String, name : String) : HTTP::Client::Response
  body = URI::Params.encode({"_csrf" => token, "version" => version, "name" => name})
  request(server, "POST", "/users/#{id}", cookie, body)
end

private def rename(server : Shomen::Server, id : Int64, name : String) : HTTP::Client::Response
  cookie, token, version = open_edit(server, id)
  post_rename(server, id, cookie, token, version, name)
end

private def rows(id : Int64) : Int32
  Users::STORE.read(after: 0_i64, limit: 10_000).count { |row| row.stream == Users.stream(id.to_s) }
end

describe Users do
  it "shows an empty form at version 0 for a user with no name" do
    response = request(Shomen::Server.new, "GET", "/users/1/edit")
    response.status_code.should eq(200)
    response.body.should contain(%(<input type="hidden" name="version" value="0">))
    response.body.should contain(%(<label for="name">Name</label>))
  end

  it "appends one event row per rename and shows the new name" do
    server = Shomen::Server.new
    response = rename(server, 2_i64, " Ada ")
    response.status_code.should eq(303)
    response.headers["Location"].should eq("/users/2")
    rows(2_i64).should eq(1)
    shown = request(server, "GET", "/users/2")
    shown.status_code.should eq(200)
    shown.body.should contain("<h1>Ada</h1>")
  end

  it "appends a second row when the same rename is sent again" do
    server = Shomen::Server.new
    rename(server, 3_i64, "Ada").status_code.should eq(303)
    rename(server, 3_i64, "Ada").status_code.should eq(303)
    rows(3_i64).should eq(2)
    request(server, "GET", "/users/3/edit").body.should contain(%(name="version" value="2"))
  end

  it "answers a stale form with 409 and adds no row" do
    server = Shomen::Server.new
    cookie, token, version = open_edit(server, 4_i64)
    rename(server, 4_i64, "Ada").status_code.should eq(303)
    response = post_rename(server, 4_i64, cookie, token, version, "Grace")
    response.status_code.should eq(409)
    response.body.should contain("<h1>Conflict</h1>")
    response.body.should_not contain("user-4")
    rows(4_i64).should eq(1)
    request(server, "GET", "/users/4").body.should contain("<h1>Ada</h1>")
  end

  it "redisplays a short name with 422 and adds no row" do
    server = Shomen::Server.new
    response = rename(server, 5_i64, " A")
    response.status_code.should eq(422)
    response.body.should contain(%(value=" A"))
    response.body.should contain("Name must be at least 2 characters")
    rows(5_i64).should eq(0)
  end

  it "returns 404 for a user with no name" do
    request(Shomen::Server.new, "GET", "/users/6").status_code.should eq(404)
  end

  it "answers a negative version with 400 and adds no row" do
    server = Shomen::Server.new
    cookie, token, _ = open_edit(server, 7_i64)
    response = post_rename(server, 7_i64, cookie, token, "-1", "Ada")
    response.status_code.should eq(400)
    response.body.should_not contain("expected_version")
    rows(7_i64).should eq(0)
  end

  it "puts the stream version in the form when another event type follows a rename" do
    server = Shomen::Server.new
    rename(server, 8_i64, "Ada").status_code.should eq(303)
    Users::STORE.append(Users.stream("8"), 1_i64, [UserNoted.new] of Shomen::Event)
    request(server, "GET", "/users/8/edit").body.should contain(%(name="version" value="2"))
    rename(server, 8_i64, "Grace").status_code.should eq(303)
    request(server, "GET", "/users/8").body.should contain("<h1>Grace</h1>")
  end
end
