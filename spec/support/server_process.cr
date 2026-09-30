require "socket"
require "http/client"

# A spec/support/server_worker.cr process on a port of its own. Its
# standard output and error go to channels line by line, so a spec waits
# for a line instead of sleeping
# (docs/decisions/20260929-phase6-process-spec.md).
class ServerProcess
  SOURCE = "spec/support/server_worker.cr"

  getter port : Int32 = 0
  @exited : Channel(Process::Status)? = nil
  @status : Process::Status? = nil

  # Runs a worker to its end and returns its status and standard error.
  def self.run(arguments : Array(String), env = {} of String => String?) : {Process::Status, String}
    database = File.tempname("shomen-worker", ".sqlite3")
    errors = IO::Memory.new
    process = Process.new(Workers.binary(SOURCE), arguments, env: worker_env(database, env), error: errors)
    done = Channel(Process::Status).new(1)
    spawn { done.send(process.wait) }
    select
    when status = done.receive
      {status, errors.to_s}
    when timeout(20.seconds)
      process.signal(Signal::KILL)
      done.receive
      raise "server_worker did not exit: #{errors}"
    end
  ensure
    remove_database(database) if database
  end

  # The worker's store is a new SQLite file unless env names another.
  def self.worker_env(database : String, env) : Hash(String, String?)
    result = {"WORKER_DATABASE_URL" => "sqlite3://#{database}"} of String => String?
    env.each { |name, value| result[name] = value }
    result
  end

  def initialize(port : Int32 = 0, mode : String = "single", timeout : Float64 = 25.0, env = {} of String => String?)
    @database = File.tempname("shomen-worker", ".sqlite3")
    @output = Channel(String?).new(64)
    @errors = Channel(String?).new(64)
    @process = Process.new(
      Workers.binary(SOURCE), [port.to_s, mode, timeout.to_s],
      env: ServerProcess.worker_env(@database, env), input: :pipe, output: :pipe, error: :pipe,
    )
    forward(@process.output, @output)
    forward(@process.error, @errors)
    begin
      @port = expect_error(/\Ashomen: listening on http:\/\/127\.0\.0\.1:(\d+)\z/)[1].to_i
    rescue ex
      # A worker that never listened is killed, waited, and its database removed.
      stop
      raise ex
    end
  end

  def expect_output(pattern : Regex, within : Time::Span = 20.seconds) : Regex::MatchData
    expect(@output, pattern, within)
  end

  def expect_error(pattern : Regex, within : Time::Span = 20.seconds) : Regex::MatchData
    expect(@errors, pattern, within)
  end

  def signal(signal : Signal = Signal::TERM) : Nil
    @process.signal(signal)
  end

  # Writes the line /worker/slow waits for.
  def release : Nil
    @process.input.puts("go")
    @process.input.flush
  end

  # Waits for the worker to exit; fails after within.
  def wait(within : Time::Span = 10.seconds) : Process::Status
    if status = @status
      return status
    end
    exited = @exited ||= begin
      channel = Channel(Process::Status).new(1)
      process = @process
      spawn { channel.send(process.wait) }
      channel
    end
    select
    when status = exited.receive
      @status = status
      status
    when timeout(within)
      raise "server_worker did not exit within #{within}"
    end
  end

  # Kills the worker if it still runs and removes its database.
  def stop : Nil
    @process.signal(Signal::KILL) unless @process.terminated?
    wait
  rescue
  ensure
    remove_database(@database)
  end

  private def forward(io : IO, lines : Channel(String?)) : Nil
    spawn do
      while line = io.gets
        lines.send(line)
      end
    rescue IO::Error
    ensure
      lines.send(nil)
    end
  end

  private def expect(lines : Channel(String?), pattern : Regex, within : Time::Span) : Regex::MatchData
    deadline = Time.instant + within
    loop do
      select
      when line = lines.receive
        raise "server_worker ended before a line matched #{pattern.source}" unless line
        if match = pattern.match(line)
          return match
        end
      when timeout(deadline - Time.instant)
        raise "no line matched #{pattern.source} within #{within}"
      end
    end
  end
end

def with_server_process(port : Int32 = 0, mode : String = "single", timeout : Float64 = 25.0, env = {} of String => String?, & : ServerProcess ->) : Nil
  server = ServerProcess.new(port, mode, timeout, env)
  begin
    yield server
  ensure
    server.stop
  end
end

# Sends a GET on socket and leaves the connection open.
def send_get(socket : IO, path : String) : Nil
  socket << "GET " << path << " HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n"
  socket.flush
end

# Reads lines from io until one equals line; fails when io ends first.
def read_until(io : IO, line : String) : Nil
  while current = io.gets
    return if current == line
  end
  raise "the stream ended before #{line.inspect}"
end
