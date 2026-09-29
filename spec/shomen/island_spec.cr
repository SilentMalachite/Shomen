require "../spec_helper"

private def script_file : String
  "src/shomen/assets/shomen.js"
end

private class ScriptPage < Shomen::View
  def to_html : String
    html lang: "en" do
      head do
        title "Script"
        shomen_script
      end
    end
  end
end

describe Shomen::Island do
  it "serves shomen.js as JavaScript" do
    response = call_with(Shomen::Server.new, "GET", "/shomen.js")
    response.status_code.should eq(200)
    response.headers["Content-Type"].should eq("text/javascript; charset=utf-8")
    response.body.should eq(File.read(script_file))
    response.headers["X-Content-Type-Options"].should eq("nosniff")
  end

  it "writes the script element for the path it serves" do
    Shomen::Island::Script.path.should eq(Shomen::View::SCRIPT_PATH)
    ScriptPage.new.to_html.should eq(
      "<!DOCTYPE html><html lang=\"en\"><head><title>Script</title>" \
      "<script src=\"/shomen.js\" defer></script></head></html>"
    )
  end

  it "has no npm dependency and stays under 10 KB" do
    source = File.read(script_file)
    source.bytesize.should be < 10_240
    source.should_not match(/\bimport\b(?!\()|\bexport\b|\brequire\s*\(/)
    source.scan(/\bimport\(/).size.should eq(1)
    source.should contain(%(import(ISLAND_PATH + name + ".js")))
    File.exists?("package.json").should be_false
    Dir.glob("src/shomen/assets/*").should eq([script_file])
  end

  it "loads island modules from the path the island routes serve" do
    File.read(script_file).should contain(%(const ISLAND_PATH = "/islands/";))
    IslandRoutes::CounterIsland.path.should eq("/islands/counter.js")
  end

  it "sets no on-handler property, so every listener goes through addEventListener" do
    File.read(script_file).should_not match(/\.on[a-z]+\s*=[^=]/)
  end

  it "uses no data attribute outside data-shomen-" do
    source = File.read(script_file)
    source.scan(/data-[a-z-]+/).map(&.[0]).reject(&.starts_with?("data-shomen-")).should be_empty
    source.should_not contain("dataset")
  end

  it "serves an island module declared with Shomen::Island.script" do
    response = call_with(Shomen::Server.new, "GET", "/islands/counter.js")
    response.status_code.should eq(200)
    response.headers["Content-Type"].should eq("text/javascript; charset=utf-8")
    response.headers["X-Content-Type-Options"].should eq("nosniff")
    response.body.should eq(File.read("spec/support/islands/counter.js"))
    IslandRoutes::CounterIsland.path.should eq("/islands/counter.js")
  end

  it "gives names that differ only by '-' routes of their own" do
    IslandRoutes::Counter_2Island.path.should eq("/islands/counter-2.js")
    IslandRoutes::Counter2Island.path.should eq("/islands/counter2.js")
  end

  it "answers a module that no island declared with 404" do
    call_with(Shomen::Server.new, "GET", "/islands/nothing.js").status_code.should eq(404)
  end

  it "fails to compile an island name that is not a plain name" do
    status, output = crystal_build_fixture("spec/fixtures/island_bad_name.cr")
    status.should_not eq(0)
    output.should contain("island name must be")
  end

  it "fails to compile an island whose file cannot be read" do
    status, output = crystal_build_fixture("spec/fixtures/island_missing_file.cr")
    status.should_not eq(0)
    output.should contain("island file not found")
  end
end
