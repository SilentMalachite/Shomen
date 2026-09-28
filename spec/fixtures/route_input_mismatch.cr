require "../../src/shomen"

class InputMismatch < Shomen::Route
  method GET
  path "/items/:id"

  struct Input
  end

  def call(input : Input) : Shomen::Response
    Shomen::Response.html("x")
  end
end

InputMismatch.handle(HTTP::Request.new("GET", "/items/1"))
