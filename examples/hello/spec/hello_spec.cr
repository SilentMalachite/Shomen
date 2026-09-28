require "./spec_helper"
require "http/client"

describe Hello::Show do
  it "returns a document containing h1 Hello" do
    io = IO::Memory.new
    request = HTTP::Request.new("GET", "/")
    response = HTTP::Server::Response.new(io)
    context = HTTP::Server::Context.new(request, response)
    Shomen::Server.new.call(context)
    response.close
    io.rewind
    parsed = HTTP::Client::Response.from_io(io)
    parsed.status_code.should eq(200)
    parsed.body.should contain("<h1>Hello</h1>")
  end

  it "exposes the declared path" do
    Hello::Show.path.should eq("/")
  end
end
