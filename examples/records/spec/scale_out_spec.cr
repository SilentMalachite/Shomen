require "./spec_helper"

private SCRIPT = "scripts/two_processes.sh"
private DOCS   = {"../../docs/en/05-SCALE-OUT.md", "../../docs/05-SCALE-OUT.md"}
private CI     = "../../.github/workflows/ci.yml"

# The bodies of the ```sh blocks in a Markdown file.
private def shell_blocks(path : String) : Array(String)
  blocks = [] of String
  current = nil
  File.each_line(path) do |line|
    if body = current
      if line == "```"
        blocks << body.to_s
        current = nil
      else
        body << line << '\n'
      end
    elsif line == "```sh"
      current = String::Builder.new
    end
  end
  blocks
end

private def links(path : String) : Array(String)
  File.read(path).scan(/\]\(([^)#:]+)(?:#[^)]*)?\)/).map(&.[1])
end

describe "docs/en/05-SCALE-OUT.md" do
  it "shows the commands CI runs for two processes, in both languages" do
    script = File.read(SCRIPT)
    DOCS.each do |path|
      shell_blocks(path).should contain(script), "#{path} has no sh block equal to #{SCRIPT}"
    end
  end

  it "is what CI runs, without and with a replica URL" do
    lines = File.read_lines(CI).map(&.strip)
    lines.count("run: sh #{SCRIPT}").should eq(2)
    lines.count(&.starts_with?("RECORDS_REPLICA_URL:")).should eq(1)
  end

  it "names the variables CI sets for the two processes" do
    ci = File.read(CI)
    {"RECORDS_DATABASE_URL", "RECORDS_REPLICA_URL", "SHOMEN_SECRET", "SHOMEN_ENV"}.each do |name|
      ci.should contain("#{name}:")
      DOCS.each { |path| File.read(path).should contain("`#{name}`") }
    end
  end

  it "links only to files that exist" do
    DOCS.each do |path|
      links(path).each do |link|
        File.exists?(File.join(File.dirname(path), link)).should be_true, "#{path} links to #{link}, which does not exist"
      end
    end
  end
end
