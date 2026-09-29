require "../spec_helper"

# Serves a fake connection on its own fiber, as Listener does, and runs
# body there. The returned channel receives once the fiber ends.
private def serve(connections : Shomen::Connections, io : IO, &body : ->) : Channel(Nil)
  ended = Channel(Nil).new(1)
  opened = Channel(Nil).new(1)
  spawn do
    connections.open(io)
    opened.send(nil)
    body.call
  ensure
    connections.leave
    ended.send(nil)
  end
  opened.receive
  ended
end

private def receive_within(channel : Channel(T), limit : Time::Span = 5.seconds) : T forall T
  select
  when value = channel.receive
    value
  when timeout(limit)
    raise "nothing arrived within #{limit}"
  end
end

describe Shomen::Connections do
  it "closes an idle connection when it drains" do
    connections = Shomen::Connections.new
    reader, writer = IO.pipe
    ended = serve(connections, reader) { reader.gets rescue nil }
    connections.drain
    receive_within(ended)
    reader.closed?.should be_true
    writer.close
  end

  it "leaves a request in progress open and waits until it ends" do
    connections = Shomen::Connections.new
    reader, writer = IO.pipe
    started = Channel(Nil).new(1)
    release = Channel(Nil).new
    ended = serve(connections, reader) do
      connections.request do
        started.send(nil)
        release.receive
      end
    end
    receive_within(started)
    connections.busy.should eq(1)
    connections.drain
    reader.closed?.should be_false
    waited = Channel(Bool).new(1)
    spawn { waited.send(connections.wait(5.seconds)) }
    Fiber.yield
    select
    when waited.receive
      fail "wait returned while a request was in progress"
    else
    end
    release.send(nil)
    receive_within(waited).should be_true
    receive_within(ended)
    connections.busy.should eq(0)
    reader.close
    writer.close
  end

  it "returns false when the limit passes first" do
    connections = Shomen::Connections.new
    reader, writer = IO.pipe
    started = Channel(Nil).new(1)
    release = Channel(Nil).new
    ended = serve(connections, reader) do
      connections.request do
        started.send(nil)
        release.receive
      end
    end
    receive_within(started)
    connections.drain
    connections.wait(10.milliseconds).should be_false
    release.send(nil)
    receive_within(ended)
    reader.close
    writer.close
  end

  it "waits for a request that begins after it drains with nothing in progress" do
    connections = Shomen::Connections.new
    reader, writer = IO.pipe
    go = Channel(Nil).new
    started = Channel(Nil).new(1)
    release = Channel(Nil).new
    ended = serve(connections, reader) do
      go.receive
      connections.request do
        started.send(nil)
        release.receive
      end
    end
    connections.drain
    go.send(nil)
    receive_within(started)
    connections.busy.should eq(1)
    connections.wait(10.milliseconds).should be_false
    waited = Channel(Bool).new(1)
    spawn { waited.send(connections.wait(5.seconds)) }
    release.send(nil)
    receive_within(waited).should be_true
    receive_within(ended)
    writer.close
  end

  it "does not wait for a stream and closes it" do
    connections = Shomen::Connections.new
    reader, writer = IO.pipe
    streaming = Channel(Nil).new(1)
    ended = serve(connections, reader) do
      connections.request do
        connections.stream
        streaming.send(nil)
        reader.gets rescue nil
      end
    end
    receive_within(streaming)
    connections.busy.should eq(0)
    connections.drain
    receive_within(ended)
    reader.closed?.should be_true
    connections.wait(5.seconds).should be_true
    writer.close
  end

  it "cuts a stream whose client stopped reading without waiting for its writes" do
    connections = Shomen::Connections.new
    listener = TCPServer.new("127.0.0.1", 0)
    client = TCPSocket.new("127.0.0.1", listener.local_address.port)
    socket = listener.accept
    socket.sync = false
    ended = serve(connections, socket) do
      connections.request do
        connections.stream
        # Small writes, as a chunked response makes: the one stuck flushes
        # the socket's buffer, which close would flush again.
        begin
          loop { socket << "data: x\n\n" }
        rescue IO::Error
        end
      end
    ensure
      socket.close rescue nil
    end
    # A write that succeeds does not yield, so the fiber is stuck in one now.
    sleep 50.milliseconds
    drained = Channel(Nil).new(1)
    spawn do
      connections.drain
      drained.send(nil)
    end
    receive_within(drained)
    receive_within(ended)
    connections.wait(5.seconds).should be_true
    client.close
    listener.close
  end

  it "closes a stream that begins after it drains" do
    connections = Shomen::Connections.new
    reader, writer = IO.pipe
    started = Channel(Nil).new(1)
    go = Channel(Nil).new
    ended = serve(connections, reader) do
      connections.request do
        started.send(nil)
        go.receive
        connections.stream
        reader.gets rescue nil
      end
    end
    receive_within(started)
    connections.drain
    reader.closed?.should be_false
    go.send(nil)
    receive_within(ended)
    reader.closed?.should be_true
    writer.close
  end

  it "says when it drains and returns at once with nothing in progress" do
    connections = Shomen::Connections.new
    connections.draining?.should be_false
    connections.drain
    connections.draining?.should be_true
    connections.wait(5.seconds).should be_true
  end

  it "runs a request on a fiber that serves no connection" do
    connections = Shomen::Connections.new
    ran = false
    connections.request { ran = true }
    connections.stream
    ran.should be_true
    connections.busy.should eq(0)
  end
end
