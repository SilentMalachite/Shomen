require "../spec_helper"

private def source(name : String) : String
  File.read("src/shomen/#{name}.cr")
end

describe "module boundaries" do
  it "keeps HTML out of the store and what it requires" do
    %w(store store_adapter sqlite_adapter postgres_adapter event recorded conflict append_signal).each do |name|
      source(name).should_not match(/Shomen::(HTML|View|ErrorView)|require "\.\/(html|view|a11y|error_view)"/)
    end
  end

  it "keeps the database out of commands, events, projections, and SSE" do
    %w(command event rejected recorded projection append_signal sse).each do |name|
      source(name).should_not match(/sqlite|postgres|\bpg\b/i)
    end
  end
end
