require "../spec_helper"

private def start_session(server : Shomen::Server) : {String, String}
  response = call_with(server, "GET", "/phase2/token")
  {session_cookie(response), response.body}
end

private def form_body(pairs : Hash(String, String)) : String
  URI::Params.encode(pairs)
end

describe "CSRF" do
  it "returns 403 HTML for a POST without a session or token" do
    response = call_with(Shomen::Server.new, "POST", "/phase2/echo", body: "")
    response.status_code.should eq(403)
    response.headers["Content-Type"].should eq("text/html; charset=utf-8")
    response.body.should contain("<title>Forbidden</title>")
    response.headers["X-Frame-Options"].should eq("DENY")
  end

  it "returns 403 when the form has no token" do
    server = Shomen::Server.new
    cookie, _ = start_session(server)
    call_with(server, "POST", "/phase2/echo", cookie: cookie, body: "name=x").status_code.should eq(403)
  end

  it "returns 403 for a wrong token" do
    server = Shomen::Server.new
    cookie, _ = start_session(server)
    response = call_with(server, "POST", "/phase2/echo", cookie: cookie, body: form_body({"_csrf" => "wrong"}))
    response.status_code.should eq(403)
  end

  it "returns 403 for another session's token" do
    server = Shomen::Server.new
    cookie, _ = start_session(server)
    _, other_token = start_session(server)
    response = call_with(server, "POST", "/phase2/echo", cookie: cookie, body: form_body({"_csrf" => other_token}))
    response.status_code.should eq(403)
  end

  it "accepts the session's token" do
    server = Shomen::Server.new
    cookie, token = start_session(server)
    response = call_with(server, "POST", "/phase2/echo", cookie: cookie, body: form_body({"_csrf" => token}))
    response.status_code.should eq(200)
    response.body.should eq("accepted")
  end

  it "accepts the session's token after a restart with the same secret" do
    cookie, token = start_session(Shomen::Server.new(secret: "k"))
    response = call_with(Shomen::Server.new(secret: "k"), "POST", "/phase2/echo", cookie: cookie, body: form_body({"_csrf" => token}))
    response.status_code.should eq(200)
  end

  it "keeps the same token for the same session" do
    server = Shomen::Server.new
    cookie, token = start_session(server)
    call_with(server, "GET", "/phase2/token", cookie: cookie).body.should eq(token)
  end

  it "accepts a charset parameter on the form content type" do
    server = Shomen::Server.new
    cookie, token = start_session(server)
    response = call_with(server, "POST", "/phase2/echo", cookie: cookie, body: form_body({"_csrf" => token}),
      content_type: "application/x-www-form-urlencoded; charset=UTF-8")
    response.status_code.should eq(200)
  end

  it "does not read the token from a body that is not urlencoded" do
    server = Shomen::Server.new
    cookie, token = start_session(server)
    response = call_with(server, "POST", "/phase2/echo", cookie: cookie, body: form_body({"_csrf" => token}),
      content_type: "multipart/form-data; boundary=x")
    response.status_code.should eq(403)
  end

  it "checks PUT, PATCH, and DELETE" do
    %w(PUT PATCH DELETE).each do |verb|
      call_with(Shomen::Server.new, verb, "/phase2/echo", body: "").status_code.should eq(403)
    end
  end

  it "does not check GET" do
    call_with(Shomen::Server.new, "GET", "/phase2/token").status_code.should eq(200)
  end

  it "returns 400 HTML for a form body that is not UTF-8" do
    server = Shomen::Server.new
    cookie, token = start_session(server)
    response = call_with(server, "POST", "/phase2/echo", cookie: cookie, body: form_body({"_csrf" => token}) + "&name=%FF")
    response.status_code.should eq(400)
    response.body.should contain("<title>Bad input</title>")
  end

  it "returns 403 for a form body without a token even when it is not UTF-8" do
    server = Shomen::Server.new
    cookie, _ = start_session(server)
    call_with(server, "POST", "/phase2/echo", cookie: cookie, body: "name=%FF").status_code.should eq(403)
  end

  it "turns Shomen::Forbidden from a route into 403 HTML" do
    response = call_with(Shomen::Server.new, "GET", "/phase2/denied")
    response.status_code.should eq(403)
    response.body.should contain("<title>Forbidden</title>")
  end
end
