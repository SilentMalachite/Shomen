require "http"

class Shomen::Response
  getter status : Int32
  getter content_type : String
  getter body : String
  getter headers : HTTP::Headers
  # The id the session remembers after this response; 0 leaves it as it
  # is (docs/decisions/20261001-phase7-remember-append.md).
  property remember : Int64 = 0_i64

  def initialize(@status : Int32, @content_type : String, @body : String, @headers : HTTP::Headers = HTTP::Headers.new)
  end

  def self.html(body : String, status : Int32 = 200) : self
    new(status, "text/html; charset=utf-8", body)
  end

  # The answer to a GET whose If-None-Match matched etag.
  def self.not_modified(etag : String, cache_control : String) : self
    response = new(304, "text/html; charset=utf-8", "")
    response.validated(etag, cache_control)
    response
  end

  # Sends etag and cache_control. A 304 sends the same Cache-Control
  # without calling the route, so a different one set here raises
  # (docs/decisions/20261001-phase7-etag.md).
  def validated(etag : String, cache_control : String) : Nil
    if (own = @headers["Cache-Control"]?) && own != cache_control
      raise ArgumentError.new("the route set Cache-Control: #{own}, which its 304 would not send; define cache_control instead")
    end
    @headers["Cache-Control"] = cache_control
    @headers["ETag"] = etag
  end

  def self.redirect(location : String, status : Int32 = 303) : self
    headers = HTTP::Headers.new
    headers["Location"] = location
    new(status, "text/html; charset=utf-8", "", headers)
  end
end
