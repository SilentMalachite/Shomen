require "../spec_helper"

describe Shomen::Response do
  it "builds an HTML response" do
    response = Shomen::Response.html("<h1>Hello</h1>")
    response.status.should eq(200)
    response.content_type.should eq("text/html; charset=utf-8")
    response.body.should eq("<h1>Hello</h1>")
  end

  it "builds a redirect" do
    response = Shomen::Response.redirect("/next")
    response.status.should eq(303)
    response.headers["Location"].should eq("/next")
  end

  it "accepts an explicit redirect status" do
    response = Shomen::Response.redirect("/gone", 302)
    response.status.should eq(302)
    response.headers["Location"].should eq("/gone")
  end
end
