require "../spec_helper"

ROTATION_OLD = "old-secret-0123456789abcdef012345"
ROTATION_NEW = "new-secret-0123456789abcdef012345"

# The session cookie and the csrf token of a GET to /phase2/token.
private def token_page(server : Shomen::Server, cookie : String? = nil) : {String, String}
  response = call_with(server, "GET", "/phase2/token", cookie: cookie)
  {session_cookie(response), response.body}
end

private def post_echo(server : Shomen::Server, cookie : String, token : String) : HTTP::Client::Response
  call_with(server, "POST", "/phase2/echo", cookie: cookie, body: URI::Params.encode({"_csrf" => token}))
end

private def cookie_value(cookie : String) : String
  cookie.split('=', 2)[1]
end

private def session_id(cookie : String) : String
  cookie_value(cookie).rpartition('.')[0]
end

describe "SHOMEN_SECRET_VERIFY" do
  it "accepts a cookie and a CSRF token signed with it, and reissues the cookie under SHOMEN_SECRET" do
    old_server = Shomen::Server.new(secret: ROTATION_OLD)
    new_server = Shomen::Server.new(secret: ROTATION_NEW, verify_secret: ROTATION_OLD)
    cookie, token = token_page(old_server)
    response = post_echo(new_server, cookie, token)
    response.status_code.should eq(200)
    reissued = session_cookie(response)
    reissued.should_not eq(cookie)
    session = Shomen::SessionStore.new(ROTATION_NEW).load(cookie_value(reissued))
    session.fresh?.should be_false
    session.id.should eq(session_id(cookie))
  end

  it "accepts a form rendered under the old secret after the cookie was reissued" do
    old_server = Shomen::Server.new(secret: ROTATION_OLD)
    new_server = Shomen::Server.new(secret: ROTATION_NEW, verify_secret: ROTATION_OLD)
    cookie, old_token = token_page(old_server)
    reissued, _ = token_page(new_server, cookie)
    post_echo(new_server, reissued, old_token).status_code.should eq(200)
  end

  it "lets a process that still signs with the old secret accept the new one while they swap" do
    before_swap = Shomen::Server.new(secret: ROTATION_OLD, verify_secret: ROTATION_NEW)
    after_swap = Shomen::Server.new(secret: ROTATION_NEW, verify_secret: ROTATION_OLD)
    cookie, token = token_page(after_swap)
    response = post_echo(before_swap, cookie, token)
    response.status_code.should eq(200)
    Shomen::SessionStore.new(ROTATION_OLD).load(cookie_value(session_cookie(response))).id.should eq(session_id(cookie))
  end

  it "refuses the old cookie and token once the verify secret is gone" do
    cookie, token = token_page(Shomen::Server.new(secret: ROTATION_OLD))
    post_echo(Shomen::Server.new(secret: ROTATION_NEW), cookie, token).status_code.should eq(403)
  end

  it "reads SHOMEN_SECRET_VERIFY and treats an empty one as unset" do
    with_env({"SHOMEN_SECRET_VERIFY" => ROTATION_OLD}) do
      Shomen::Server.verify_secret_from_env.should eq(ROTATION_OLD)
    end
    with_env({"SHOMEN_SECRET_VERIFY" => ""}) do
      Shomen::Server.verify_secret_from_env.should be_nil
    end
  end
end
