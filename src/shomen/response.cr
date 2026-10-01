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

  def self.redirect(location : String, status : Int32 = 303) : self
    headers = HTTP::Headers.new
    headers["Location"] = location
    new(status, "text/html; charset=utf-8", "", headers)
  end
end
