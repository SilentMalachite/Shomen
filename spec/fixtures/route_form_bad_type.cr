require "../../src/shomen"

class FormBadType < Shomen::Route
  method POST
  path "/items"

  struct Input
    getter price : Float64

    def initialize(@price : Float64)
    end
  end

  def call(input : Input) : Shomen::Response
    Shomen::Response.html("x")
  end
end

FormBadType.handle(HTTP::Request.new("POST", "/items"))
