require "../spec_helper"

private def source(name : String) : String
  File.read("src/shomen/#{name}.cr")
end

describe "phase 3 module boundaries" do
  it "keeps HTML out of the store and what it requires" do
    %w(store event recorded conflict).each do |name|
      source(name).should_not match(/Shomen::(HTML|View|ErrorView)|require "\.\/(html|view|a11y|error_view)"/)
    end
  end

  it "keeps SQLite out of commands, events, and projections" do
    %w(command event rejected recorded projection).each do |name|
      source(name).should_not match(/sqlite/i)
    end
  end
end
