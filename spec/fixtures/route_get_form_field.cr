require "../../src/shomen"

class GetFormField < Shomen::Route
  method GET
  path "/items"

  struct Input
    getter name : String

    def initialize(@name : String)
    end
  end

  def call(input : Input) : Shomen::Response
    Shomen::Response.html("x")
  end
end

GetFormField.handle(HTTP::Request.new("GET", "/items"))
