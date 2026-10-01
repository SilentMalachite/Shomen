require "../../src/shomen"

class ValidatorNotString < Shomen::Route
  method GET
  path "/items"

  struct Input
  end

  def validator(input : Input)
    1
  end

  def call(input : Input) : Shomen::Response
    Shomen::Response.html("x")
  end
end

ValidatorNotString.handle(HTTP::Request.new("GET", "/items"))
