# A spec/support/consumer_worker.cr process. Its standard output goes to a
# channel line by line, so a spec waits for a line instead of sleeping
# (docs/decisions/20260929-phase6-process-spec.md).
class ConsumerProcess
  SOURCE = "spec/support/consumer_worker.cr"

  @status : Process::Status? = nil

  def initialize(url : String, mode : String)
    @lines = Channel(String?).new(64)
    @process = Process.new(Workers.binary(SOURCE), [url, mode], input: :pipe, output: :pipe, error: :inherit)
    lines = @lines
    output = @process.output
    spawn do
      while line = output.gets
        lines.send(line)
      end
    rescue IO::Error
    ensure
      lines.send(nil)
    end
    expect("started")
  end

  def expect(line : String, within : Time::Span = 20.seconds) : Nil
    deadline = Time.instant + within
    loop do
      select
      when received = @lines.receive
        raise "consumer_worker ended before #{line.inspect}" unless received
        return if received == line
      when timeout(deadline - Time.instant)
        raise "consumer_worker did not write #{line.inspect} within #{within}"
      end
    end
  end

  # Asks the worker to stop its consumer and close its store, and waits
  # for it to exit successfully.
  def finish(within : Time::Span = 10.seconds) : Nil
    @process.input.puts("stop")
    @process.input.flush
    status = wait(within)
    raise "consumer_worker exited with #{status.exit_code}" unless status.success?
  end

  def kill : Nil
    return if @status
    @process.signal(Signal::KILL) unless @process.terminated?
    wait(10.seconds)
  end

  private def wait(within : Time::Span) : Process::Status
    if status = @status
      return status
    end
    done = Channel(Process::Status).new(1)
    process = @process
    spawn { done.send(process.wait) }
    select
    when status = done.receive
      @status = status
    when timeout(within)
      raise "consumer_worker did not exit within #{within}"
    end
  end
end

def with_consumer_process(url : String, mode : String = "run", & : ConsumerProcess ->) : Nil
  process = ConsumerProcess.new(url, mode)
  begin
    yield process
  ensure
    process.kill
  end
end
