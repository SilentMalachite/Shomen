require "../spec_helper"

describe Shomen::Event do
  it "returns the name the type declares" do
    SpecEvents::Noted.new("a").event_type.should eq("spec.noted")
    SpecEvents::Noted::EVENT_TYPE.should eq("spec.noted")
  end

  it "decodes a payload by its declared name" do
    at = Time.utc(2026, 9, 29, 1, 2, 3)
    event = Shomen::Event.decode("spec.renamed", SpecEvents::Renamed.new("Ada", at).to_json)
    event.should be_a(SpecEvents::Renamed)
    event.as(SpecEvents::Renamed).name.should eq("Ada")
    event.at.should eq(at)
  end

  it "keeps the time to the second" do
    at = Time.utc(2026, 9, 29, 1, 2, 3, nanosecond: 500_000_000)
    decoded = Shomen::Event.decode("spec.noted", SpecEvents::Noted.new("a", at).to_json)
    decoded.at.should eq(Time.utc(2026, 9, 29, 1, 2, 3))
  end

  it "raises for a name no type declares" do
    expect_raises(ArgumentError, %(unknown event type "gone")) do
      Shomen::Event.decode("gone", "{}")
    end
  end

  it "fails to compile an event without event_type" do
    status, output = crystal_build_fixture("spec/fixtures/event_missing_type.cr")
    status.should_not eq(0)
    output.should contain("event_type")
  end

  it "fails to compile two events with one event_type" do
    status, output = crystal_build_fixture("spec/fixtures/event_duplicate_type.cr")
    status.should_not eq(0)
    output.should contain("both declare event_type")
  end
end
