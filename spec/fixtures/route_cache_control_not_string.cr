require "../../src/shomen"

class CacheControlNotString < Shomen::Route
  method GET
  path "/items"

  struct Input
  end

  def validator(input : Input) : String
    "v"
  end

  def cache_control
    60
  end

  def call(input : Input) : Shomen::Response
    Shomen::Response.html("x")
  end
end

CacheControlNotString.handle(HTTP::Request.new("GET", "/items"))
