require "./spec_helper"

describe Shomen do
  it "has a non-empty VERSION" do
    Shomen::VERSION.empty?.should be_false
  end
end
