require "./spec_helper"
require "socket"
require "../../../spec/support/browser"
require "../scale_out/two_processes"

# Answers every request with the same HTML page, as another application
# on the port would.
private def with_other_server(& : String ->) : Nil
  server = HTTP::Server.new do |context|
    context.response.content_type = "text/html"
    context.response.print "<p>other</p>"
  end
  address = server.bind_tcp("127.0.0.1", 0)
  spawn { server.listen }
  begin
    yield "http://127.0.0.1:#{address.port}"
  ensure
    server.close
  end
end

# A port on 127.0.0.1 that nothing listens on.
private def closed_port : Int32
  server = TCPServer.new("127.0.0.1", 0)
  port = server.local_address.port
  server.close
  port
end

describe TwoProcesses do
  it "passes when the second server shows what the first registered" do
    with_live_server do |first|
      with_live_server do |second|
        TwoProcesses.run(URI.parse(first), URI.parse(second), "TP-SPEC1")
      end
    end
    Items.find("TP-SPEC1", 0_i64).should_not be_nil
  end

  it "fails when the second server is not a records process" do
    with_live_server do |first|
      with_other_server do |second|
        expect_raises(TwoProcesses::Failed, "did not answer an event stream") do
          TwoProcesses.run(URI.parse(first), URI.parse(second), "TP-SPEC2")
        end
      end
    end
  end

  it "fails when a server does not answer in time" do
    with_live_server do |first|
      second = URI.parse("http://127.0.0.1:#{closed_port}")
      expect_raises(TwoProcesses::Failed, "did not answer GET /items with 200 within") do
        TwoProcesses.run(URI.parse(first), second, "TP-SPEC3", ready_within: 300.milliseconds)
      end
    end
  end

  it "makes tags the registration form accepts" do
    TwoProcesses.new_tag.should match(/\ATP-[0-9A-F]{8}\z/)
  end
end
