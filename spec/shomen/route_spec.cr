require "../spec_helper"

class PendingRoot::Show < Shomen::Route
  method GET
  path "/phase1/root"

  struct Input
  end

  def call(input : Input) : Shomen::Response
    Shomen::Response.html("root")
  end
end

class Users::Show < Shomen::Route
  method GET
  path "/phase1/users/:id"

  struct Input
    getter id : Int32

    def initialize(@id : Int32)
    end
  end

  def call(input : Input) : Shomen::Response
    Shomen::Response.html(input.id.to_s)
  end
end

class SlashItems::Show < Shomen::Route
  method GET
  path "/phase1/slash/:id/"

  struct Input
    getter id : Int32

    def initialize(@id : Int32)
    end
  end

  def call(input : Input) : Shomen::Response
    Shomen::Response.html(input.id.to_s)
  end
end

class Labels::Show < Shomen::Route
  method GET
  path "/phase1/labels/:name"

  struct Input
    getter name : String

    def initialize(@name : String)
    end
  end

  def call(input : Input) : Shomen::Response
    Shomen::Response.html(input.name)
  end
end

describe Shomen::Route do
  it "returns a static path from the route class" do
    PendingRoot::Show.path.should eq("/phase1/root")
    PendingRoot::Show.verb.should eq("GET")
    PendingRoot::Show.pattern.should eq("/phase1/root")
  end

  it "fills one path parameter" do
    Users::Show.path(id: 15).should eq("/phase1/users/15")
  end

  it "builds a path when the caller has a variable named io" do
    io = "alice"
    Labels::Show.path(name: io.upcase).should eq("/phase1/labels/ALICE")
  end

  it "rejects a path component that would add a segment" do
    expect_raises(ArgumentError) do
      Labels::Show.path(name: "a/b")
    end
  end

  it "builds Input from the request path" do
    response = Users::Show.handle(HTTP::Request.new("GET", "/phase1/users/15"))
    response.status.should eq(200)
    response.body.should eq("15")
  end

  it "raises BadInput when an integer segment is not an integer" do
    expect_raises(Shomen::BadInput) do
      Users::Show.handle(HTTP::Request.new("GET", "/phase1/users/abc"))
    end
  end

  it "decodes a path segment back to the original string" do
    Labels::Show.path(name: "東京").should eq("/phase1/labels/%E6%9D%B1%E4%BA%AC")
    response = Labels::Show.handle(HTTP::Request.new("GET", "/phase1/labels/%E6%9D%B1%E4%BA%AC"))
    response.status.should eq(200)
    response.body.should eq("東京")
  end

  it "raises BadInput when a segment is not valid UTF-8" do
    expect_raises(Shomen::BadInput) do
      Labels::Show.handle(HTTP::Request.new("GET", "/phase1/labels/%FF"))
    end
  end

  it "raises BadInput when an integer segment is only whitespace around digits" do
    expect_raises(Shomen::BadInput) do
      Users::Show.handle(HTTP::Request.new("GET", "/phase1/users/%2015"))
    end
  end

  it "keeps a trailing slash on a parameterized path" do
    url = SlashItems::Show.path(id: 7)
    url.should eq("/phase1/slash/7/")
    SlashItems::Show.handle(HTTP::Request.new("GET", url)).body.should eq("7")
  end

  it "rejects a route that does not declare path" do
    status, output = crystal_build_fixture("spec/fixtures/route_missing_path.cr")
    status.should_not eq(0)
    output.should contain("must declare path")
  end

  it "rejects an Input field type outside String, Int32, and Int64" do
    status, output = crystal_build_fixture("spec/fixtures/route_bad_input_type.cr")
    status.should_not eq(0)
    output.should contain("String, Int32, or Int64")
  end

  it "rejects an Input that does not match path params" do
    status, output = crystal_build_fixture("spec/fixtures/route_input_mismatch.cr")
    status.should_not eq(0)
    output.should contain("must match path params")
  end

  it "renders a view with the status the route asks for" do
    response = ServerRoutes::Invalid.handle(HTTP::Request.new("POST", "/phase2/invalid"))
    response.status.should eq(422)
    response.content_type.should eq("text/html; charset=utf-8")
    response.body.should contain("<h1>Hello</h1>")
  end
end
