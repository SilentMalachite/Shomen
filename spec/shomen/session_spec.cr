require "../spec_helper"

private def session_header(response : HTTP::Client::Response) : String
  response.headers.get("Set-Cookie").find(&.starts_with?("shomen_session=")) || raise "no session cookie"
end

describe "Shomen::Server sessions" do
  it "sets a session cookie on a response to a request without one" do
    header = session_header(call_with(Shomen::Server.new, "GET", "/phase1/home"))
    header.should contain("HttpOnly")
    header.should contain("SameSite=Lax")
    header.should_not contain("Secure")
  end

  it "sets a session cookie on a 404 too" do
    response = call_with(Shomen::Server.new, "GET", "/phase2/missing")
    response.status_code.should eq(404)
    session_header(response).should start_with("shomen_session=")
  end

  it "does not set the cookie again when the request carries a valid one" do
    server = Shomen::Server.new
    cookie = session_cookie(call_with(server, "GET", "/phase1/home"))
    response = call_with(server, "GET", "/phase1/home", cookie: cookie)
    response.headers.has_key?("Set-Cookie").should be_false
  end

  it "replaces a cookie signed with another secret" do
    cookie = session_cookie(call_with(Shomen::Server.new(secret: "a"), "GET", "/phase1/home"))
    response = call_with(Shomen::Server.new(secret: "b"), "GET", "/phase1/home", cookie: cookie)
    session_header(response).should start_with("shomen_session=")
  end

  it "marks the cookie Secure when the server runs behind HTTPS" do
    header = session_header(call_with(Shomen::Server.new(https: true), "GET", "/phase1/home"))
    header.should contain("Secure")
  end
end
