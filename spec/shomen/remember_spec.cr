require "../spec_helper"

private def post(path : String) : HTTP::Request
  HTTP::Request.new("POST", path)
end

# A new session's cookie and csrf token.
private def open_session(server : Shomen::Server) : {String, String}
  page = call_with(server, "GET", "/phase2/token")
  {session_cookie(page), page.body}
end

describe "a route that remembers an append" do
  it "raises must_see to the id it remembers" do
    response = RememberRoutes::Remember.handle(post("/phase7/remember"), URI::Params.parse("id=7"), "t", 5_i64)
    response.body.should eq("7")
    response.remember.should eq(7_i64)
  end

  it "keeps a higher must_see when it remembers a lower id" do
    response = RememberRoutes::Remember.handle(post("/phase7/remember"), URI::Params.parse("id=3"), "t", 5_i64)
    response.body.should eq("5")
    response.remember.should eq(5_i64)
  end

  it "ignores an id that is not positive" do
    response = RememberRoutes::Remember.handle(post("/phase7/remember"), URI::Params.parse("id=0"), "t")
    response.remember.should eq(0_i64)
  end

  it "leaves the response without an id when it does not remember" do
    RememberRoutes::MustSee.handle(HTTP::Request.new("GET", "/phase7/must-see"), URI::Params.new, "t", 5_i64).remember.should eq(0_i64)
  end
end

describe "Shomen::Server and the id a session remembers" do
  it "sets shomen_append for a route that remembers, and the session's next request must see the id" do
    server = Shomen::Server.new
    cookie, token = open_session(server)
    posted = call_with(server, "POST", "/phase7/remember", cookie, "_csrf=#{token}&id=42")
    posted.status_code.should eq(200)
    append = append_cookie?(posted) || fail "no shomen_append cookie"
    append.should start_with("shomen_append=42.")
    call_with(server, "GET", "/phase7/must-see", "#{cookie}; #{append}").body.should eq("42")
  end

  it "sets no shomen_append for a request that remembers nothing" do
    server = Shomen::Server.new
    cookie, _ = open_session(server)
    response = call_with(server, "GET", "/phase7/must-see", cookie)
    response.body.should eq("0")
    append_cookie?(response).should be_nil
  end

  it "sets no shomen_append when the route raises after it remembered" do
    server = Shomen::Server.new
    cookie, token = open_session(server)
    response = call_with(server, "POST", "/phase7/remember-conflict", cookie, "_csrf=#{token}")
    response.status_code.should eq(409)
    append_cookie?(response).should be_nil
  end

  it "forgets the id once the cookie expired" do
    server = Shomen::Server.new
    cookie, _ = open_session(server)
    sessions = Shomen::SessionStore.new(Shomen::Server.secret_from_env)
    session = sessions.load(cookie.lchop("shomen_session="))
    expired = sessions.append_cookie(session, 42_i64, false, Time.utc - Shomen::Session::REMEMBER)
    current = sessions.append_cookie(session, 42_i64, false)
    call_with(server, "GET", "/phase7/must-see", "#{cookie}; shomen_append=#{expired.value}").body.should eq("0")
    call_with(server, "GET", "/phase7/must-see", "#{cookie}; shomen_append=#{current.value}").body.should eq("42")
  end

  it "ignores the append cookie of another session" do
    server = Shomen::Server.new
    cookie, token = open_session(server)
    other, _ = open_session(server)
    append = append_cookie?(call_with(server, "POST", "/phase7/remember", cookie, "_csrf=#{token}&id=42")) || fail "no shomen_append cookie"
    call_with(server, "GET", "/phase7/must-see", "#{other}; #{append}").body.should eq("0")
  end
end
