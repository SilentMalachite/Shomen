require "../../src/shomen"

class BadInputType < Shomen::Route
  method GET
  path "/items/:id"

  struct Input
    getter id : Bool

    def initialize(@id : Bool)
    end
  end

  def call(input : Input) : Shomen::Response
    Shomen::Response.html("x")
  end
end

BadInputType.handle(HTTP::Request.new("GET", "/items/1"))
