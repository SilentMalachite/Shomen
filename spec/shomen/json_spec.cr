require "../spec_helper"

private def accepting_json : HTTP::Headers
  HTTP::Headers{"Accept" => "application/json"}
end

describe "JSON responses" do
  it "sends JSON from a route that calls json" do
    response = call_with(Shomen::Server.new, "GET", "/phase4/json")
    response.status_code.should eq(201)
    response.headers["Content-Type"].should eq("application/json")
    response.body.should eq(%({"name":"<Ada>","count":2}))
    response.headers["X-Content-Type-Options"].should eq("nosniff")
  end

  it "keeps HTML for an HTML route when the client accepts JSON" do
    response = call_with(Shomen::Server.new, "GET", "/phase1/home", headers: accepting_json)
    response.headers["Content-Type"].should eq("text/html; charset=utf-8")
    response.body.should contain("<h1>Hello</h1>")
  end

  it "answers errors with HTML documents when the client accepts JSON" do
    ["/phase4/json/missing", "/phase4/json/nowhere"].each do |path|
      response = call_with(Shomen::Server.new, "GET", path, headers: accepting_json)
      response.status_code.should eq(404)
      response.headers["Content-Type"].should eq("text/html; charset=utf-8")
      response.body.should contain("<title>Not found</title>")
    end
  end
end
