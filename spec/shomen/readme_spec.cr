require "../spec_helper"

private def links(path : String) : Array(String)
  File.read(path).scan(/\]\(([^)#:]+)(?:#[^)]*)?\)/).map(&.[1])
end

describe "README and CONTRIBUTING" do
  {"README.md", "README.ja.md", "CONTRIBUTING.md", "CONTRIBUTING.ja.md"}.each do |path|
    it "#{path} points at the API list, the scale-out steps, and examples/records" do
      found = links(path).map(&.rstrip('/'))
      found.any?(&.ends_with?("04-API.md")).should be_true, "#{path} has no link to 04-API.md"
      found.any?(&.ends_with?("05-SCALE-OUT.md")).should be_true, "#{path} has no link to 05-SCALE-OUT.md"
      found.should contain("examples/records")
    end

    it "#{path} links only to files that exist" do
      links(path).each do |link|
        File.exists?(link).should be_true, "#{path} links to #{link}, which does not exist"
      end
    end
  end
end
