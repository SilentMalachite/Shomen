require "../spec_helper"

describe Shomen::Command do
  it "returns events when the input is valid" do
    result = SpecEvents::Note.new("hello").call
    result.should be_a(Array(Shomen::Event))
    result.as(Array(Shomen::Event)).first.as(SpecEvents::Noted).text.should eq("hello")
  end

  it "returns Rejected with messages when the input is invalid" do
    result = SpecEvents::Note.new("").call
    result.should be_a(Shomen::Rejected)
    result.as(Shomen::Rejected).messages.should eq(["text must not be empty"])
  end
end
