require "http"
require "./response"
require "./store"
require "./fragment"
require "./unavailable"

# An event stream a route opens with sse. It sends the fragment's HTML
# first, then again after each append the store learns of, through this
# process or another, that changed it.
class Shomen::SSE < Shomen::Response
  HEARTBEAT = 15.seconds
  # How long a stream waits before it renders again after a render raised
  # Shomen::Unavailable (docs/decisions/20261001-phase7-remember-append.md).
  RETRY = 200.milliseconds

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
  # fragment receives the id of the append each render must see, 0 for the
  # first.
  def initialize(@store : Shomen::Store, @fragment : Int64 -> Shomen::Fragment, @heartbeat : Time::Span = HEARTBEAT)
    @seen = @store.last_appended
    @html = @fragment.call(0_i64).to_html
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
        seen = @store.last_appended
        html = begin
          @fragment.call(seen).to_html
        rescue Shomen::Unavailable
          # A read model has not reached the append yet. The stream keeps the
          # id it waits past, so it renders again; the heartbeat goes on.
          sleep({RETRY, left}.min)
          next
        end
        @seen = seen
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
