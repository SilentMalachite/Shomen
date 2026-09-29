require "../spec_helper"

describe "an unhandled Shomen::Conflict" do
  it "returns a 409 HTML document without the exception message" do
    response = call_with(Shomen::Server.new, "GET", "/phase3/conflict")
    response.status_code.should eq(409)
    response.headers["Content-Type"].should eq("text/html; charset=utf-8")
    response.body.should start_with("<!DOCTYPE html>")
    response.body.should contain("<h1>Conflict</h1>")
    response.body.should contain(Shomen::Server::CONFLICT_DETAIL)
    response.body.should_not contain("secret-7")
  end
end
