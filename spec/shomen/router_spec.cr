require "../spec_helper"

def crystal_run_fixture(path : String) : {Int32, String}
  output = IO::Memory.new
  status = Process.run(
    "crystal",
    ["run", "--error-trace", File.expand_path(path)],
    output: output,
    error: output,
  )
  {status.exit_code || 1, output.to_s}
ensure
  binary = path.sub(/\.cr$/, "")
  File.delete(binary) if File.exists?(binary)
end

describe Shomen::Router do
  it "prefers a static route over a parameter route" do
    handler = Shomen::Router.find("GET", "/phase1/people/new").not_nil!
    handler.call(HTTP::Request.new("GET", "/phase1/people/new"), URI::Params.new, "").body.should eq("new")
  end

  it "prefers a static route when the segment is percent-encoded" do
    handler = Shomen::Router.find("GET", "/phase1/people/%6Eew").not_nil!
    handler.call(HTTP::Request.new("GET", "/phase1/people/%6Eew"), URI::Params.new, "").body.should eq("new")
  end

  it "captures an integer segment" do
    handler = Shomen::Router.find("GET", "/phase1/people/8").not_nil!
    handler.call(HTTP::Request.new("GET", "/phase1/people/8"), URI::Params.new, "").body.should eq("8")
  end

  it "ignores the query string" do
    handler = Shomen::Router.find("GET", HTTP::Request.new("GET", "/phase1/people/8?x=1").path)
    handler.should_not be_nil
  end

  it "treats a different method as no match" do
    Shomen::Router.find("POST", "/phase1/people/8").should be_nil
    Shomen::Router.find("POST", "/phase1/home").should_not be_nil
  end

  it "does not match a different number of segments" do
    Shomen::Router.find("GET", "/phase1/people/8/edit").should be_nil
    Shomen::Router.find("GET", "/phase1/people").should be_nil
  end

  it "rejects two routes with the same method and path" do
    status, output = crystal_run_fixture("spec/fixtures/duplicate_route.cr")
    status.should_not eq(0)
    output.should contain("duplicate route")
  end

  it "rejects two routes with the same method and shape" do
    status, output = crystal_run_fixture("spec/fixtures/duplicate_shape.cr")
    status.should_not eq(0)
    output.should contain("duplicate route")
  end
end
