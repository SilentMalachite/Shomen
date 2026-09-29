require "../spec_helper"

private def targeted(*values : String) : HTTP::Headers
  headers = HTTP::Headers.new
  values.each { |value| headers.add("Shomen-Target", value) }
  headers
end

describe "fragment requests" do
  it "renders the document without Shomen-Target" do
    response = call_with(Shomen::Server.new, "GET", "/phase4/note")
    response.status_code.should eq(200)
    response.body.should start_with("<!DOCTYPE html>")
    response.body.should contain("<div id=\"note\"><p>&lt;saved&gt;</p></div>")
  end

  it "renders only the fragment with Shomen-Target" do
    response = call_with(Shomen::Server.new, "GET", "/phase4/note", headers: targeted("note"))
    response.status_code.should eq(200)
    response.body.should eq("<div id=\"note\"><p>&lt;saved&gt;</p></div>")
  end

  it "gives the route the target id" do
    call_with(Shomen::Server.new, "GET", "/phase4/target", headers: targeted("a&b")).body.should eq("a&amp;b")
    call_with(Shomen::Server.new, "GET", "/phase4/target").body.should eq("none")
  end

  it "gives the target to a POST that passes the csrf check" do
    server = Shomen::Server.new
    first = call_with(server, "GET", "/phase2/token")
    body = URI::Params.encode({"_csrf" => first.body})
    response = call_with(server, "POST", "/phase4/target", session_cookie(first), body, headers: targeted("box"))
    response.status_code.should eq(200)
    response.body.should eq("box")
  end

  it "answers a malformed Shomen-Target with 400" do
    ["", "a b", "a\tb", "a,b"].each do |value|
      response = call_with(Shomen::Server.new, "GET", "/phase4/target", headers: targeted(value))
      response.status_code.should eq(400)
      response.body.should contain("<title>Bad input</title>")
    end
    call_with(Shomen::Server.new, "GET", "/phase4/target", headers: targeted("a", "b")).status_code.should eq(400)
  end

  it "sends Vary: Shomen-Target on every response" do
    ["/phase4/note", "/phase1/missing", "/phase1/boom", "/phase1/redirect"].each do |path|
      call_with(Shomen::Server.new, "GET", path).headers["Vary"].should eq("Shomen-Target")
    end
  end
end
