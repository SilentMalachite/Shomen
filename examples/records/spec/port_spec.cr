require "./spec_helper"

private def with_port(value : String?, &)
  before = ENV["RECORDS_PORT"]?
  value ? (ENV["RECORDS_PORT"] = value) : ENV.delete("RECORDS_PORT")
  yield
ensure
  before ? (ENV["RECORDS_PORT"] = before) : ENV.delete("RECORDS_PORT")
end

describe "Records.port" do
  it "is 3000 when RECORDS_PORT is unset" do
    with_port(nil) { Records.port.should eq(3000) }
  end

  it "reads RECORDS_PORT" do
    with_port("8080") { Records.port.should eq(8080) }
  end

  it "rejects a RECORDS_PORT that is not a port number" do
    ["", " 8080", "http", "0", "-1", "65536"].each do |value|
      with_port(value) { expect_raises(ArgumentError, "RECORDS_PORT") { Records.port } }
    end
  end
end
