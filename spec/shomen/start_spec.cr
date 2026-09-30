require "../spec_helper"

describe "Shomen::Server.start" do
  it "shares a port between two processes with reuse_port" do
    with_server_process(mode: "reuse") do |first|
      with_server_process(port: first.port, mode: "reuse") do |second|
        second.port.should eq(first.port)
        HTTP::Client.get("http://127.0.0.1:#{first.port}/worker/ping").body.should eq("pong")
      end
    end
  end

  it "does not share a port without reuse_port" do
    with_server_process(mode: "reuse") do |first|
      status, errors = ServerProcess.run([first.port.to_s, "single", "1"])
      status.success?.should be_false
      errors.should contain("Address already in use")
    end
  end

  it "fails in production without SHOMEN_SECRET and names the variable" do
    status, errors = ServerProcess.run(["0", "single", "1"], {"SHOMEN_ENV" => "production", "SHOMEN_SECRET" => nil})
    status.success?.should be_false
    errors.should contain("SHOMEN_SECRET must be set to at least 32 bytes when SHOMEN_ENV=production")
  end

  it "starts in production with a SHOMEN_SECRET of 32 bytes" do
    with_server_process(env: {"SHOMEN_ENV" => "production", "SHOMEN_SECRET" => LONG_SECRET}) do |server|
      HTTP::Client.get("http://127.0.0.1:#{server.port}/worker/ping").body.should eq("pong")
    end
  end
end
