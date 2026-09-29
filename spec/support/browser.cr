require "http/client"
require "http/server"
require "http/web_socket"
require "json"
require "file_utils"

# Drives a headless Chrome over the DevTools protocol with the standard
# library alone. Browser.executable is nil when no Chrome is found.
class Browser
  LIMIT      = 20.seconds
  MAC_CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

  def self.executable : String?
    if path = ENV["SHOMEN_CHROME"]?.presence
      return path
    end
    return MAC_CHROME if File.exists?(MAC_CHROME)
    Process.find_executable("google-chrome") ||
      Process.find_executable("chromium") ||
      Process.find_executable("chromium-browser")
  end

  # Chrome prints the address it listens on to stderr. A fiber reads it so
  # the wait can be bounded; the rest of the output is read and dropped so
  # the pipe never fills.
  def self.endpoint(error : IO) : {String, Int32}
    found = Channel({String, Int32}?).new(1)
    spawn do
      address = nil
      while line = error.gets
        if match = line.match(/DevTools listening on ws:\/\/([^\/:]+):(\d+)\//)
          address = {match[1], match[2].to_i}
          break
        end
      end
      found.send(address)
      drain(error)
    rescue IO::Error
      found.send(nil) rescue nil
    end
    select
    when address = found.receive
      address || raise "Chrome exited before it listened"
    when timeout(LIMIT)
      raise "Chrome did not listen within #{LIMIT}"
    end
  end

  def self.drain(io : IO) : Nil
    while io.gets
    end
  rescue IO::Error
  end

  @profile : String
  @socket : HTTP::WebSocket?
  @inbox = Channel(JSON::Any).new(256)
  @events = [] of JSON::Any
  @next_id = 0

  def initialize(executable : String)
    @profile = File.tempname("shomen-chrome")
    Dir.mkdir(@profile)
    @process = Process.new(executable, [
      "--headless",
      "--disable-gpu",
      "--no-first-run",
      "--no-default-browser-check",
      "--user-data-dir=#{@profile}",
      "--remote-debugging-port=0",
      "about:blank",
    ], error: :pipe)
    begin
      host, port = Browser.endpoint(@process.error)
      page = JSON.parse(HTTP::Client.new(host, port).exec("PUT", "/json/new?about:blank").body)
      socket = HTTP::WebSocket.new(URI.parse(page["webSocketDebuggerUrl"].as_s))
      @socket = socket
      inbox = @inbox
      socket.on_message { |message| inbox.send(JSON.parse(message)) }
      spawn do
        socket.run
      rescue IO::Error
      end
      command("Page.enable")
    rescue ex
      shutdown
      raise ex
    end
  end

  # Loads url and returns after its load event.
  def visit(url : String) : Nil
    @events.clear
    command("Page.navigate", {url: url})
    wait_for("Page.loadEventFired")
  end

  # Runs a script in the page and returns its value. A promise is awaited.
  def evaluate(expression : String) : JSON::Any
    result = command("Runtime.evaluate", {expression: expression, awaitPromise: true, returnByValue: true})
    if details = result["exceptionDetails"]?
      raise "script failed: #{details.to_json}"
    end
    result["result"]["value"]? || JSON::Any.new(nil)
  end

  # Forgets buffered events, so the next wait_for sees only later ones.
  def clear_events : Nil
    @events.clear
  end

  def wait_for(event : String) : JSON::Any
    if index = @events.index { |message| message["method"]?.try(&.as_s?) == event }
      return @events.delete_at(index)
    end
    loop do
      message = receive
      return message if message["method"]?.try(&.as_s?) == event
      @events << message
    end
  end

  def command(method : String, params = NamedTuple.new) : JSON::Any
    @next_id += 1
    id = @next_id
    socket.send({id: id, method: method, params: params}.to_json)
    loop do
      message = receive
      if message["id"]?.try(&.as_i?) == id
        if error = message["error"]?
          raise "#{method} failed: #{error.to_json}"
        end
        return message["result"]
      end
      @events << message
    end
  end

  def close : Nil
    shutdown
  end

  private def socket : HTTP::WebSocket
    @socket || raise "not connected"
  end

  # Asks Chrome to quit so it removes its own lock and socket files, waits
  # up to LIMIT, and kills it only after that. Then removes the profile.
  private def shutdown : Nil
    exited = Channel(Nil).new(1)
    process = @process
    spawn do
      process.wait
      exited.send(nil)
    end
    if socket = @socket
      begin
        socket.send({id: @next_id += 1, method: "Browser.close"}.to_json)
      rescue IO::Error
        process.terminate(graceful: false) unless process.terminated?
      end
    else
      process.terminate(graceful: false) unless process.terminated?
    end
    select
    when exited.receive
    when timeout(LIMIT)
      process.terminate(graceful: false) unless process.terminated?
      select
      when exited.receive
      when timeout(LIMIT)
      end
    end
    begin
      @socket.try(&.close)
    rescue IO::Error
    end
    remove_profile
  end

  # Helper processes can touch the profile briefly after Chrome exits, so a
  # failed removal is retried a bounded number of times, then raised.
  private def remove_profile : Nil
    attempts = 0
    while Dir.exists?(@profile)
      begin
        FileUtils.rm_r(@profile)
      rescue ex : File::Error
        attempts += 1
        raise ex if attempts >= 10
        Fiber.yield
      end
    end
  end

  private def receive : JSON::Any
    select
    when message = @inbox.receive
      message
    when timeout(LIMIT)
      raise "no message from Chrome within #{LIMIT}"
    end
  end
end

def with_browser(& : Browser ->) : Nil
  browser = Browser.new(Browser.executable || raise "no Chrome found; set SHOMEN_CHROME")
  begin
    yield browser
  ensure
    browser.close
  end
end

# Serves Shomen::Server on an ephemeral port on 127.0.0.1 for a browser.
def with_live_server(& : String ->) : Nil
  server = HTTP::Server.new([Shomen::Server.new])
  address = server.bind_tcp("127.0.0.1", 0)
  spawn { server.listen }
  begin
    yield "http://127.0.0.1:#{address.port}"
  ensure
    server.close
  end
end
