require "../../src/shomen"

class CachedBadKey < Shomen::Route
  method GET
  path "/items"

  struct Input
  end

  def call(input : Input) : Shomen::Response
    render_fragment(cached(Shomen::FragmentCache.new, "items", :symbol) { Shomen::CachedFragment.new("x") })
  end
end

CachedBadKey.handle(HTTP::Request.new("GET", "/items"))
