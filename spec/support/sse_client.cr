require "http"

# Sends a GET through Shomen::Server#call with the response going into a
# pipe, and reads it as an event stream. An SSE response does not end by
# itself, so call_with cannot read one. The response is HTTP/1.0, so the
# body arrives unchunked. Each read waits up to LIMIT.
class SSEClient
  LIMIT = 5.seconds

  getter status : Int32
  getter headers = HTTP::Headers.new
  @reader : IO::FileDescriptor
  @finished : Channel(Nil)

  def initialize(server : Shomen::Server, path : String)
    reader, writer = IO.pipe
    reader.read_timeout = LIMIT
    @reader = reader
    @finished = Channel(Nil).new(1)
    finished = @finished
    spawn do
      response = HTTP::Server::Response.new(writer)
      response.version = "HTTP/1.0"
      begin
        server.call(HTTP::Server::Context.new(HTTP::Request.new("GET", path), response))
        response.close
      rescue HTTP::Server::ClientError
      end
      writer.close rescue nil
      finished.send(nil)
    end
    head = reader.gets(chomp: true) || raise "no status line"
    @status = head.split(' ')[1].to_i
    while (line = reader.gets(chomp: true)) && !line.empty?
      name, _, value = line.partition(": ")
      @headers.add(name, value)
    end
  end

  # The next block up to the blank line that ends it: a message's data
  # lines joined with "\n", or ":" for a comment.
  def next_block : String
    data = [] of String
    comment = false
    loop do
      line = @reader.gets(chomp: true) || raise "the stream ended"
      if line.empty?
        return data.join("\n") unless data.empty?
        return ":" if comment
      elsif line.starts_with?(':')
        comment = true
      elsif line.starts_with?("data: ")
        data << line.lchop("data: ")
      else
        raise "unexpected line #{line.inspect}"
      end
    end
  end

  # The next message, past any comments.
  def next_message : String
    loop do
      block = next_block
      return block unless block == ":"
    end
  end

  # Closes the client's end, as a browser that leaves does.
  def close : Nil
    @reader.close
  end

  # Waits until Shomen::Server#call has returned.
  def wait_finished : Nil
    select
    when @finished.receive
    when timeout(LIMIT)
      raise "the server did not finish within #{LIMIT}"
    end
  end
end

# The stream of the routes in SSERoutes ends within a heartbeat after
# close, so wait_finished returns.
def with_sse_client(path : String, & : SSEClient ->) : Nil
  client = SSEClient.new(Shomen::Server.new, path)
  begin
    yield client
  ensure
    client.close
    client.wait_finished
  end
end
