require "../../src/shomen"

class CacheControlWithoutValidator < Shomen::Route
  method GET
  path "/items"

  struct Input
  end

  def cache_control : String
    "private, max-age=60"
  end

  def call(input : Input) : Shomen::Response
    Shomen::Response.html("x")
  end
end

CacheControlWithoutValidator.handle(HTTP::Request.new("GET", "/items"))
