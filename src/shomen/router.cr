require "http"
require "uri"

module Shomen::Router
  def self.captures!(pattern : String, path : String) : Hash(String, String)
    expected = pattern.split("/")
    actual = path.split("/")
    unless expected.size == actual.size
      raise Shomen::NotFound.new
    end
    found = {} of String => String
    expected.each_with_index do |part, index|
      got = actual[index]
      if part.starts_with?(":")
        raise Shomen::NotFound.new if got.empty?
        found[part[1..]] = decode_segment!(got)
      else
        decoded = decode_segment(got)
        raise Shomen::NotFound.new if decoded.nil? || part != decoded
      end
    end
    found
  end

  record Entry, verb : String, pattern : String, shape : String, literals : Int32, handler : Proc(HTTP::Request, Shomen::Response)

  @@entries : Array(Entry)?

  def self.entries : Array(Entry)
    @@entries ||= build_entries
  end

  def self.find(method : String, path : String) : Proc(HTTP::Request, Shomen::Response)?
    matches = entries.select { |entry| entry.verb == method && match?(entry.pattern, path) }
    return nil if matches.empty?
    exact = matches.find { |entry| entry.pattern == path }
    return exact.handler if exact
    best = matches.max_of { |entry| entry.literals }
    top = matches.select { |entry| entry.literals == best }
    if top.size > 1
      raise "ambiguous route #{method} #{path}"
    end
    top.first.handler
  end

  def self.match?(pattern : String, path : String) : Bool
    expected = pattern.split("/")
    actual = path.split("/")
    return false unless expected.size == actual.size
    expected.each_with_index do |part, index|
      got = actual[index]
      if part.starts_with?(":")
        return false if got.empty?
        decode_segment!(got)
      else
        decoded = decode_segment(got)
        return false if decoded.nil? || part != decoded
      end
    end
    true
  end

  # Decode one segment after split so %2F stays inside the segment.
  # + stays +; invalid UTF-8 is nil.
  private def self.decode_segment(segment : String) : String?
    decoded = URI.decode(segment)
    decoded if decoded.valid_encoding?
  end

  private def self.decode_segment!(segment : String) : String
    decode_segment(segment) || raise Shomen::BadInput.new("invalid path segment")
  end

  def self.shape_for(pattern : String) : String
    pattern.split("/").map { |part| part.starts_with?(":") ? ":" : part }.join("/")
  end

  def self.literal_count(pattern : String) : Int32
    pattern.split("/").count { |part| !part.empty? && !part.starts_with?(":") }
  end

  private def self.build_entries : Array(Entry)
    built = [] of Entry
    seen = {} of String => String
    {% for klass in Shomen::Route.all_subclasses %}
      {% if !klass.abstract? %}
        {% unless klass.has_constant?("VERB") && klass.has_constant?("PATH") %}
          {% raise "#{klass.name.stringify} must declare method and path" %}
        {% end %}
        verb = {{klass}}.verb
        pattern = {{klass}}.pattern
        shape = shape_for(pattern)
        key = verb + " " + shape
        if seen[key]?
          raise "duplicate route #{verb} #{pattern}"
        end
        seen[key] = pattern
        built << Entry.new(
          verb,
          pattern,
          shape,
          literal_count(pattern),
          ->(request : HTTP::Request) { {{klass}}.handle(request) },
        )
      {% end %}
    {% end %}
    built
  end
end
