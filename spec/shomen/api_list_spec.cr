require "../spec_helper"

# The public types under Shomen, found at compile time
# (docs/decisions/20261001-phase8-api-list.md).
private def public_types : Set(String)
  {% begin %}
    {% names = ["Shomen"] %}
    {% queue = [Shomen] %}
    {% for type in queue %}
      {% for name in type.constants %}
        {% found = type.constant(name) %}
        {% if found.is_a?(TypeNode) && !found.private? %}
          {% names << found.stringify %}
          {% queue << found %}
        {% end %}
      {% end %}
    {% end %}
    {{names}}.to_set
  {% end %}
end

private HEADING = /\A### `(Shomen(?:::[A-Za-z0-9_]+)*)`\z/

private def headings(path : String) : Array(String)
  File.read_lines(path).compact_map { |line| HEADING.match(line).try(&.[1]) }
end

private def listed(path : String) : Set(String)
  headings(path).to_set
end

private def links(path : String) : Array(String)
  File.read(path).scan(/\]\(([^)#:]+)(?:#[^)]*)?\)/).map(&.[1])
end

describe "docs/en/04-API.md" do
  it "lists every public type under Shomen, and no other" do
    listed("docs/en/04-API.md").should eq(public_types)
  end

  it "has the same types as its Japanese translation" do
    listed("docs/04-API.md").should eq(listed("docs/en/04-API.md"))
  end

  it "has one heading for each type" do
    {"docs/en/04-API.md", "docs/04-API.md"}.each do |path|
      names = headings(path)
      names.select { |name| names.count(name) > 1 }.uniq.should eq([] of String), "#{path} lists a type twice"
    end
  end

  it "links only to files that exist" do
    {"docs/en/04-API.md", "docs/04-API.md"}.each do |path|
      links(path).each do |link|
        File.exists?(File.join(File.dirname(path), link)).should be_true, "#{path} links to #{link}, which does not exist"
      end
    end
  end

  it "does not list a private type" do
    public_types.should_not contain("Shomen::Connections::Entry")
  end
end
