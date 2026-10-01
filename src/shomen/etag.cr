require "digest/sha256"
require "./build_id"

# The weak ETag of a GET route's validator
# (docs/decisions/20261001-phase7-etag.md).
module Shomen::ETag
  # Each value goes in after its byte length, so moving the boundary
  # between two values changes the tag.
  def self.tag(validator : String, csrf_token : String, target : String?, build_id : String = Shomen::BUILD_ID) : String
    digest = Digest::SHA256.new
    {build_id, csrf_token, target || "", validator}.each do |value|
      digest.update("#{value.bytesize}:")
      digest.update(value)
    end
    %(W/"#{digest.hexfinal[0, 32]}")
  end

  # Weak comparison against each tag in an If-None-Match header.
  def self.match?(header : String?, tag : String) : Bool
    return false unless header
    opaque = tag.lchop("W/")
    header.split(',').any? do |item|
      value = item.strip
      value == "*" || value.lchop("W/") == opaque
    end
  end
end
