require "../spec_helper"

private def connect(port : Int32) : TCPSocket
  socket = TCPSocket.new("127.0.0.1", port)
  socket.read_timeout = 20.seconds
  socket
end

describe "Shomen::Server.start on SIGTERM and SIGINT" do
  it "finishes a request in progress with Connection: close, closes an idle connection, refuses a new one, and exits 0" do
    with_server_process do |server|
      idle = connect(server.port)
      send_get(idle, "/worker/ping")
      first = HTTP::Client::Response.from_io(idle)
      first.body.should eq("pong")
      first.headers["Connection"].should eq("keep-alive")

      busy = connect(server.port)
      send_get(busy, "/worker/slow")
      server.expect_output(/\Aslow\z/)

      server.signal
      server.expect_error(/\Ashomen: shutting down\z/)
      idle.gets.should be_nil
      expect_raises(Socket::ConnectError) { TCPSocket.new("127.0.0.1", server.port) }

      server.release
      response = HTTP::Client::Response.from_io(busy)
      response.status_code.should eq(200)
      response.body.should eq("slow done")
      response.headers["Connection"].should eq("close")
      server.wait.exit_code.should eq(0)
    end
  end

  it "shuts down the same way on SIGINT and exits 0" do
    with_server_process do |server|
      idle = connect(server.port)
      send_get(idle, "/worker/ping")
      HTTP::Client::Response.from_io(idle).body.should eq("pong")

      server.signal(Signal::INT)
      server.expect_error(/\Ashomen: shutting down\z/)
      idle.gets.should be_nil
      server.wait.exit_code.should eq(0)
    end
  end

  it "exits when the limit passes with a request still in progress" do
    with_server_process(timeout: 0.2) do |server|
      busy = connect(server.port)
      send_get(busy, "/worker/slow")
      server.expect_output(/\Aslow\z/)
      server.signal
      server.wait.exit_code.should eq(0)
    end
  end

  it "closes an SSE stream and does not wait for it" do
    with_server_process(timeout: 60.0) do |server|
      stream = connect(server.port)
      send_get(stream, "/worker/stream")
      read_until(stream, %(data: <p id="count">0</p>))
      server.signal
      server.wait.exit_code.should eq(0)
      while stream.gets
      end
    end
  end

  it "stops at once on a second signal" do
    with_server_process do |server|
      busy = connect(server.port)
      send_get(busy, "/worker/slow")
      server.expect_output(/\Aslow\z/)
      server.signal(Signal::TERM)
      server.expect_error(/\Ashomen: shutting down\z/)
      server.signal(Signal::INT)
      status = server.wait
      status.signal_exit?.should be_true
      status.exit_signal?.should eq(Signal::INT)
    end
  end

  it "stops at once on a second signal while a request blocks the event loop" do
    with_server_process do |server|
      busy = connect(server.port)
      send_get(busy, "/worker/stall")
      server.expect_output(/\Astall\z/)
      server.signal(Signal::TERM)
      server.expect_error(/\Ashomen: shutting down\z/)
      server.release
      server.expect_output(/\Astalling\z/)
      server.signal(Signal::INT)
      status = server.wait(within: 1.second)
      status.signal_exit?.should be_true
      status.exit_signal?.should eq(Signal::INT)
    end
  end

  it "stops at once, by the second signal, when two arrive together" do
    with_server_process do |server|
      client = connect(server.port)
      send_get(client, "/worker/signals")
      status = server.wait
      status.signal_exit?.should be_true
      status.exit_signal?.should eq(Signal::INT)
    end
  end
end
