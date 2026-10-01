require "./spec_helper"
require "yaml"

describe Shomen do
  it "has a non-empty VERSION" do
    Shomen::VERSION.empty?.should be_false
  end

  it "has the version shard.yml declares" do
    Shomen::VERSION.should eq(YAML.parse(File.read("shard.yml"))["version"].as_s)
  end

  it "is version 0.1.0" do
    Shomen::VERSION.should eq("0.1.0")
  end
end
