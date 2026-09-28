require "../../src/shomen"

class MissingPath < Shomen::Route
  method GET

  struct Input
  end

  def call(input : Input) : Shomen::Response
    Shomen::Response.html("x")
  end
end

MissingPath.handle(HTTP::Request.new("GET", "/"))
