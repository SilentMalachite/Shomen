require "http/client"
require "random/secure"
require "uri"

# Checks two examples/records processes on one database: an item
# registered through the first appears on the pages the second serves,
# with the session the first started, and reaches an SSE client connected
# to the second (docs/en/05-SCALE-OUT.md). It speaks HTTP only.
module TwoProcesses
  READY = 60.seconds
  WAIT  = 10.seconds

  class Failed < Exception
  end

  def self.new_tag : String
    "TP-#{Random::Secure.hex(4).upcase}"
  end

  # Raises Failed with what did not hold.
  def self.run(first : URI, second : URI, tag : String = new_tag, ready_within : Time::Span = READY) : Nil
    ready(first, ready_within)
    ready(second, ready_within)
    client = HTTP::Client.new(second)
    client.read_timeout = WAIT
    client.get("/items/live") do |stream|
      unless stream.status_code == 200 && stream.headers["Content-Type"]? == "text/event-stream"
        raise Failed.new("GET #{second}/items/live did not answer an event stream")
      end
      # The list as it is now, so the stream is open before the append.
      skip_message(stream.body_io, second)
      cookies = register(first, tag)
      show(second, "/items/#{tag}", cookies, "<h1>#{tag} ")
      show(second, "/items", cookies, %(href="/items/#{tag}"))
      unless sent?(stream.body_io, %(href="/items/#{tag}"))
        raise Failed.new("the stream from #{second} did not send #{tag} within #{WAIT}")
      end
    end
  rescue error : IO::TimeoutError
    raise Failed.new("no answer within #{WAIT}: #{error.message}")
  ensure
    client.try &.close
  end

  private def self.ready(origin : URI, within : Time::Span) : Nil
    deadline = Time.instant + within
    loop do
      begin
        return if HTTP::Client.get(origin.resolve("/items")).status_code == 200
      rescue Socket::Error | IO::Error
      end
      raise Failed.new("#{origin} did not answer GET /items with 200 within #{within}") if Time.instant > deadline
      sleep 100.milliseconds
    end
  end

  private def self.skip_message(io : IO, origin : URI) : Nil
    while line = io.gets(chomp: true)
      return if line.empty?
    end
    raise Failed.new("the stream from #{origin} ended before its first message")
  end

  private def self.sent?(io : IO, text : String) : Bool
    deadline = Time.instant + WAIT
    while Time.instant < deadline && (line = io.gets(chomp: true))
      return true if line.includes?(text)
    end
    false
  end

  private def self.register(origin : URI, tag : String) : HTTP::Cookies
    cookies = HTTP::Cookies.new
    page = request(origin, "GET", "/items/new", cookies)
    token = page.body.match(/name="_csrf" value="([^"]+)"/).try(&.[1])
    raise Failed.new("GET #{origin}/items/new has no _csrf field") unless token
    form = URI::Params.encode({"_csrf" => token, "tag" => tag, "name" => "Two-process check"})
    response = request(origin, "POST", "/items", cookies, form)
    unless response.status_code == 303 && response.headers["Location"]? == "/items/#{tag}"
      raise Failed.new("POST #{origin}/items answered #{response.status_code}, not 303 to /items/#{tag}")
    end
    cookies
  end

  private def self.show(origin : URI, path : String, cookies : HTTP::Cookies, text : String) : Nil
    response = request(origin, "GET", path, cookies)
    unless response.status_code == 200 && response.body.includes?(text)
      raise Failed.new("GET #{origin}#{path} answered #{response.status_code} without #{text}")
    end
  end

  # Sends the cookies and keeps the ones the response sets.
  private def self.request(origin : URI, method : String, path : String, cookies : HTTP::Cookies, form : String? = nil) : HTTP::Client::Response
    headers = HTTP::Headers.new
    headers["Content-Type"] = "application/x-www-form-urlencoded" if form
    cookies.add_request_headers(headers)
    client = HTTP::Client.new(origin)
    client.read_timeout = WAIT
    response = client.exec(method, path, headers, form)
    response.cookies.each { |cookie| cookies << cookie }
    response
  ensure
    client.try &.close
  end
end
