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
    source.should_not match(/\bimport\b|\bexport\b|\brequire\s*\(/)
    File.exists?("package.json").should be_false
    Dir.glob("src/shomen/assets/*").should eq([script_file])
  end

  it "uses no data attribute outside data-shomen-" do
    source = File.read(script_file)
    source.scan(/data-[a-z-]+/).map(&.[0]).reject(&.starts_with?("data-shomen-")).should be_empty
    source.should_not contain("dataset")
  end
end
