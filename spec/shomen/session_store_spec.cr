require "../spec_helper"

private def cookie_value(store : Shomen::SessionStore, session : Shomen::Session) : String
  store.cookie(session, false).value
end

describe Shomen::SessionStore do
  it "creates a fresh session when there is no cookie" do
    session = Shomen::SessionStore.new("k").load(nil)
    session.fresh?.should be_true
    session.id.should match(/\A[0-9a-f]{64}\z/)
    session.csrf_token.should_not be_empty
  end

  it "loads the same session from its signed cookie" do
    store = Shomen::SessionStore.new("k")
    first = store.load(nil)
    again = store.load(cookie_value(store, first))
    again.fresh?.should be_false
    again.id.should eq(first.id)
    again.csrf_token.should eq(first.csrf_token)
  end

  it "gives each session its own csrf token" do
    store = Shomen::SessionStore.new("k")
    store.load(nil).csrf_token.should_not eq(store.load(nil).csrf_token)
  end

  it "replaces a session whose signature was changed" do
    store = Shomen::SessionStore.new("k")
    first = store.load(nil)
    value = cookie_value(store, first)
    tampered = value[0..-2] + (value[-1] == '0' ? "1" : "0")
    again = store.load(tampered)
    again.fresh?.should be_true
    again.id.should_not eq(first.id)
  end

  it "replaces a session signed with another secret" do
    store = Shomen::SessionStore.new("a")
    first = store.load(nil)
    forged = Shomen::SessionStore.new("b").cookie(first, false).value
    store.load(forged).fresh?.should be_true
  end

  it "keeps a validly signed session across a restart with the same secret" do
    first_store = Shomen::SessionStore.new("k")
    first = first_store.load(nil)
    again = Shomen::SessionStore.new("k").load(cookie_value(first_store, first))
    again.fresh?.should be_false
    again.id.should eq(first.id)
    again.csrf_token.should eq(first.csrf_token)
  end

  it "replaces a malformed cookie" do
    store = Shomen::SessionStore.new("k")
    ["", "abc", ".", "abc.", ".abc"].each do |value|
      store.load(value).fresh?.should be_true
    end
  end

  it "writes HttpOnly, SameSite=Lax, and path=/ without Secure over HTTP" do
    store = Shomen::SessionStore.new("k")
    header = store.cookie(store.load(nil), false).to_set_cookie_header
    header.should start_with("shomen_session=")
    header.should contain("path=/")
    header.should contain("HttpOnly")
    header.should contain("SameSite=Lax")
    header.should_not contain("Secure")
  end

  it "adds Secure over HTTPS" do
    store = Shomen::SessionStore.new("k")
    store.cookie(store.load(nil), true).to_set_cookie_header.should contain("Secure")
  end

  it "loads a cookie signed with the verify secret and marks it for reissue" do
    old = Shomen::SessionStore.new("old")
    first = old.load(nil)
    rotated = Shomen::SessionStore.new("new", "old")
    again = rotated.load(cookie_value(old, first))
    again.fresh?.should be_false
    again.reissue?.should be_true
    again.id.should eq(first.id)
    again.csrf_token.should_not eq(first.csrf_token)
  end

  it "does not reissue a cookie signed with the secret" do
    store = Shomen::SessionStore.new("new", "old")
    first = store.load(nil)
    store.load(cookie_value(store, first)).reissue?.should be_false
  end

  it "signs only with the secret" do
    store = Shomen::SessionStore.new("new", "old")
    value = cookie_value(store, store.load(nil))
    Shomen::SessionStore.new("new").load(value).fresh?.should be_false
    Shomen::SessionStore.new("old").load(value).fresh?.should be_true
  end

  it "accepts a csrf token made with either secret" do
    old = Shomen::SessionStore.new("old")
    first = old.load(nil)
    rotated = Shomen::SessionStore.new("new", "old")
    again = rotated.load(cookie_value(old, first))
    rotated.csrf_valid?(again, first.csrf_token).should be_true
    rotated.csrf_valid?(again, again.csrf_token).should be_true
    rotated.csrf_valid?(again, "wrong").should be_false
    Shomen::SessionStore.new("new").csrf_valid?(again, first.csrf_token).should be_false
  end
end

# The session that cookie_value(store, session) loads again, with the
# append cookie made for it.
private def remembered(store : Shomen::SessionStore, session : Shomen::Session, append : String?, now : Time = Time.utc) : Int64
  store.load(cookie_value(store, session), append, now).remembered
end

describe "Shomen::SessionStore and the id a session remembers" do
  it "remembers nothing without the append cookie" do
    store = Shomen::SessionStore.new("k")
    session = store.load(nil)
    session.remembered.should eq(0_i64)
    remembered(store, session, nil).should eq(0_i64)
  end

  it "loads the id from the append cookie of the same session" do
    store = Shomen::SessionStore.new("k")
    session = store.load(nil)
    append = store.append_cookie(session, 42_i64, false).value
    remembered(store, session, append).should eq(42_i64)
  end

  it "forgets the id once the cookie expired" do
    store = Shomen::SessionStore.new("k")
    session = store.load(nil)
    now = Time.utc
    append = store.append_cookie(session, 42_i64, false, now).value
    remembered(store, session, append, now + Shomen::Session::REMEMBER - 1.second).should eq(42_i64)
    remembered(store, session, append, now + Shomen::Session::REMEMBER).should eq(0_i64)
  end

  it "ignores the append cookie of another session" do
    store = Shomen::SessionStore.new("k")
    other = store.load(nil)
    append = store.append_cookie(other, 42_i64, false).value
    remembered(store, store.load(nil), append).should eq(0_i64)
  end

  it "ignores the append cookie with a fresh session" do
    store = Shomen::SessionStore.new("k")
    session = store.load(nil)
    append = store.append_cookie(session, 42_i64, false).value
    store.load(nil, append).remembered.should eq(0_i64)
  end

  it "ignores an append cookie whose id or expiry was changed" do
    store = Shomen::SessionStore.new("k")
    session = store.load(nil)
    id, expires, signature = store.append_cookie(session, 42_i64, false).value.split('.')
    remembered(store, session, "43.#{expires}.#{signature}").should eq(0_i64)
    remembered(store, session, "#{id}.#{expires.to_i64 + 3600}.#{signature}").should eq(0_i64)
  end

  it "ignores a malformed append cookie" do
    store = Shomen::SessionStore.new("k")
    session = store.load(nil)
    expires = (Time.utc + 1.minute).to_unix
    ["", "42", "42.#{expires}", "..", "x.#{expires}.ab", "0.#{expires}.ab", "-1.#{expires}.ab", "42.#{expires}.ab.cd"].each do |value|
      remembered(store, session, value).should eq(0_i64)
    end
  end

  it "ignores an append cookie signed with another secret" do
    store = Shomen::SessionStore.new("a")
    session = store.load(nil)
    append = Shomen::SessionStore.new("b").append_cookie(session, 42_i64, false).value
    remembered(store, session, append).should eq(0_i64)
  end

  it "loads an append cookie signed with the verify secret" do
    old = Shomen::SessionStore.new("old")
    session = old.load(nil)
    append = old.append_cookie(session, 42_i64, false).value
    rotated = Shomen::SessionStore.new("new", "old")
    rotated.load(cookie_value(old, session), append).remembered.should eq(42_i64)
  end

  it "writes the append cookie with the session cookie's attributes and a max-age" do
    store = Shomen::SessionStore.new("k")
    header = store.append_cookie(store.load(nil), 42_i64, false).to_set_cookie_header
    header.should start_with("shomen_append=42.")
    header.should contain("path=/")
    header.should contain("max-age=60")
    header.should contain("HttpOnly")
    header.should contain("SameSite=Lax")
    header.should_not contain("Secure")
    store.append_cookie(store.load(nil), 42_i64, true).to_set_cookie_header.should contain("Secure")
  end
end
