require "../spec_helper"

describe "an unhandled Shomen::Unavailable" do
  it "returns a 503 HTML document without the exception message" do
    response = call_with(Shomen::Server.new, "GET", "/phase7/unavailable")
    response.status_code.should eq(503)
    response.headers["Content-Type"].should eq("text/html; charset=utf-8")
    response.body.should start_with("<!DOCTYPE html>")
    response.body.should contain("<h1>Unavailable</h1>")
    response.body.should contain(Shomen::Server::UNAVAILABLE_DETAIL)
    response.body.should_not contain("secret-8")
  end
end
