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
end
