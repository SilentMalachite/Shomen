require "http"
require "./response"
require "./store"
require "./fragment"

# An event stream a route opens with sse. It sends the fragment's HTML
# first, then again after each append the store learns of, through this
# process or another, that changed it.
class Shomen::SSE < Shomen::Response
  HEARTBEAT = 15.seconds

  # One message. Each line of the HTML goes in its own data line, so a line
  # break in the text cannot end the message or start another field.
  def self.message(html : String) : String
    String.build do |io|
      html.split(/\r\n|\r|\n/).each { |line| io << "data: " << line << '\n' }
      io << '\n'
    end
  end

  @seen : Int64
  @html : String
  @written : Time::Instant

  # The first render runs here, inside the route, so an error in it is an
  # ordinary error document rather than a broken stream. The last id is
  # read before it, so an append during the render still wakes the stream.
  def initialize(@store : Shomen::Store, @fragment : -> Shomen::Fragment, @heartbeat : Time::Span = HEARTBEAT)
    @seen = @store.last_appended
    @html = @fragment.call.to_html
    @written = Time.instant
    super(200, "text/event-stream", "", HTTP::Headers{"Cache-Control" => "no-store"})
  end

  # Returns only by raising when a write fails, which is how a stream
  # learns that its client left.
  def run(io : IO) : Nil
    write(io, Shomen::SSE.message(@html))
    loop do
      left = @written + @heartbeat - Time.instant
      if left.positive? && @store.wait_for_append(after: @seen, within: left)
        @seen = @store.last_appended
        html = @fragment.call.to_html
        next if html == @html
        @html = html
        write(io, Shomen::SSE.message(html))
      else
        write(io, ":\n\n")
      end
    end
  end

  private def write(io : IO, text : String) : Nil
    io << text
    io.flush
    @written = Time.instant
  end
end
