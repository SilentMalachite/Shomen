require "../../src/shomen"

class PostValidator < Shomen::Route
  method POST
  path "/items"

  struct Input
  end

  def validator(input : Input) : String
    "v"
  end

  def call(input : Input) : Shomen::Response
    Shomen::Response.html("x")
  end
end

PostValidator.handle(HTTP::Request.new("POST", "/items"))
