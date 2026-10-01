require "../spec_helper"

describe Shomen::ETag do
  it "has a build id of 32 hex digits" do
    Shomen::BUILD_ID.should match(/\A[0-9a-f]{32}\z/)
  end

  it "makes a weak tag" do
    Shomen::ETag.tag("v", "t", nil).should match(/\AW\/"[0-9a-f]{32}"\z/)
  end

  it "changes with the validator, the token, the target, and the build id" do
    tag = Shomen::ETag.tag("v", "t", nil, "b")
    Shomen::ETag.tag("v", "t", nil, "b").should eq(tag)
    Shomen::ETag.tag("w", "t", nil, "b").should_not eq(tag)
    Shomen::ETag.tag("v", "u", nil, "b").should_not eq(tag)
    Shomen::ETag.tag("v", "t", "list", "b").should_not eq(tag)
    Shomen::ETag.tag("v", "t", nil, "c").should_not eq(tag)
  end

  it "keeps values apart when the boundary between them moves" do
    Shomen::ETag.tag("bc", "a", nil, "b").should_not eq(Shomen::ETag.tag("c", "ab", nil, "b"))
  end

  it "matches the same tag, with or without W/, and inside a list" do
    tag = Shomen::ETag.tag("v", "t", nil)
    Shomen::ETag.match?(tag, tag).should be_true
    Shomen::ETag.match?(tag.lchop("W/"), tag).should be_true
    Shomen::ETag.match?(%(W/"other", #{tag} ,"x"), tag).should be_true
    Shomen::ETag.match?("*", tag).should be_true
  end

  it "does not match another tag, an empty header, or none" do
    tag = Shomen::ETag.tag("v", "t", nil)
    Shomen::ETag.match?(Shomen::ETag.tag("w", "t", nil), tag).should be_false
    Shomen::ETag.match?("", tag).should be_false
    Shomen::ETag.match?(nil, tag).should be_false
  end
end

private def get(path : String, if_none_match : String? = nil) : HTTP::Request
  headers = HTTP::Headers.new
  headers["If-None-Match"] = if_none_match if if_none_match
  HTTP::Request.new("GET", path, headers)
end

private def if_none_match(tag : String) : HTTP::Headers
  HTTP::Headers{"If-None-Match" => tag}
end

describe "a GET route with a validator" do
  it "answers a matching If-None-Match with 304 without calling the route or the view" do
    ETagRoutes::CALLS.clear
    tag = Shomen::ETag.tag("1", "t", nil)
    response = ETagRoutes::Page.handle(get("/phase7/etag/1", tag), URI::Params.new, "t")
    response.status.should eq(304)
    response.body.should eq("")
    response.headers["ETag"].should eq(tag)
    response.headers["Cache-Control"].should eq("private, no-cache")
    ETagRoutes::CALLS.should eq(["validator"])
  end

  it "sends a 200 with the ETag when the tag does not match, after the validator ran" do
    ETagRoutes::CALLS.clear
    response = ETagRoutes::Page.handle(get("/phase7/etag/2", Shomen::ETag.tag("1", "t", nil)), URI::Params.new, "t")
    response.status.should eq(200)
    response.body.should contain("<h1>2</h1>")
    response.headers["ETag"].should eq(Shomen::ETag.tag("2", "t", nil))
    response.headers["Cache-Control"].should eq("private, no-cache")
    ETagRoutes::CALLS.should eq(["validator", "call", "view"])
  end

  it "keeps the Cache-Control the route set" do
    response = ETagRoutes::OwnCacheControl.handle(get("/phase7/etag-own-cache"), URI::Params.new, "t")
    response.headers["ETag"].should eq(Shomen::ETag.tag("own", "t", nil))
    response.headers["Cache-Control"].should eq("private, max-age=60")
  end

  it "sends no ETag with a redirect" do
    response = ETagRoutes::Moved.handle(get("/phase7/etag-moved"), URI::Params.new, "t")
    response.status.should eq(303)
    response.headers.has_key?("ETag").should be_false
  end

  it "sends no ETag with an event stream" do
    with_store do |store, _|
      ETagRoutes.store = store
      response = ETagRoutes::Stream.handle(get("/phase7/etag-stream"), URI::Params.new, "t")
      response.should be_a(Shomen::SSE)
      response.headers.has_key?("ETag").should be_false
    ensure
      ETagRoutes.store = nil
    end
  end

  it "fails to compile on a route that is not GET" do
    status, output = crystal_build_fixture("spec/fixtures/route_post_validator.cr")
    status.should_not eq(0)
    output.should contain("only a GET route may define validator")
  end

  it "fails to compile when the validator does not return a String" do
    status, output = crystal_build_fixture("spec/fixtures/route_validator_not_string.cr")
    status.should_not eq(0)
    output.should contain("type must be String")
  end
end

describe "a GET route without a validator" do
  it "sends no ETag" do
    response = ServerRoutes::Home.handle(get("/phase1/home", "*"), URI::Params.new, "t")
    response.status.should eq(200)
    response.headers.has_key?("ETag").should be_false
  end
end

describe "Shomen::Server and ETag" do
  it "answers the same session's matching If-None-Match with 304 and does not call the view" do
    server = Shomen::Server.new
    page = call_with(server, "GET", "/phase2/token")
    cookie, token = session_cookie(page), page.body
    first = call_with(server, "GET", "/phase7/etag/1", cookie)
    first.status_code.should eq(200)
    tag = first.headers["ETag"]
    tag.should eq(Shomen::ETag.tag("1", token, nil))
    ETagRoutes::CALLS.clear
    second = call_with(server, "GET", "/phase7/etag/1", cookie, headers: if_none_match(tag))
    second.status_code.should eq(304)
    second.body.should eq("")
    second.headers["ETag"].should eq(tag)
    second.headers["Vary"].should eq(Shomen::Route::TARGET_HEADER)
    ETagRoutes::CALLS.should eq(["validator"])
  end

  it "sends a full 200 for the old ETag after the session changes" do
    server = Shomen::Server.new
    first = call_with(server, "GET", "/phase7/etag/1", session_cookie(call_with(server, "GET", "/phase2/token")))
    ETagRoutes::CALLS.clear
    response = call_with(server, "GET", "/phase7/etag/1", session_cookie(call_with(server, "GET", "/phase2/token")), headers: if_none_match(first.headers["ETag"]))
    response.status_code.should eq(200)
    response.body.should contain("<h1>1</h1>")
    ETagRoutes::CALLS.should eq(["validator", "call", "view"])
  end

  it "sends a full 200 for an ETag from another build" do
    server = Shomen::Server.new
    page = call_with(server, "GET", "/phase2/token")
    cookie, token = session_cookie(page), page.body
    old = Shomen::ETag.tag("1", token, nil, "another build")
    response = call_with(server, "GET", "/phase7/etag/1", cookie, headers: if_none_match(old))
    response.status_code.should eq(200)
    response.headers["ETag"].should_not eq(old)
  end

  it "sends a full 200 for a document's ETag when shomen.js asks for a fragment" do
    server = Shomen::Server.new
    page = call_with(server, "GET", "/phase2/token")
    cookie, token = session_cookie(page), page.body
    headers = if_none_match(Shomen::ETag.tag("1", token, nil))
    headers[Shomen::Route::TARGET_HEADER] = "page"
    response = call_with(server, "GET", "/phase7/etag/1", cookie, headers: headers)
    response.status_code.should eq(200)
    response.headers["ETag"].should eq(Shomen::ETag.tag("1", token, "page"))
  end
end
