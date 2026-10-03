require "./spec_helper"

private def available(tag : String) : Items::Item
  Items::Item.new(tag, "Laptop", nil, 1_i64, 1_i64)
end

private def lent(tag : String, borrower : String) : Items::Item
  Items::Item.new(tag, "Laptop", borrower, 2_i64, 2_i64)
end

describe Items::RegisterItem do
  it "registers a trimmed name" do
    events = Items::RegisterItem.new("PC-1", "  Laptop ", false).call.as(Array(Shomen::Event))
    events.size.should eq(1)
    event = events[0].as(Items::ItemRegistered)
    event.tag.should eq("PC-1")
    event.name.should eq("Laptop")
  end

  it "rejects a tag a path cannot carry or that is not capitals, digits, and hyphens" do
    ["", "pc-1", "PC/1", "PC?1", "PC#1", ".", "..", "-PC", "P" * 21].each do |tag|
      Items::RegisterItem.new(tag, "Laptop", false).call.as(Shomen::Rejected).messages.should eq([Items::RegisterItem::TAG_MESSAGE])
    end
    Items::RegisterItem.new("P" * 20, "Laptop", false).call.should be_a(Array(Shomen::Event))
  end

  it "rejects an empty or long name" do
    ["", "   ", "N" * 81].each do |name|
      Items::RegisterItem.new("PC-2", name, false).call.as(Shomen::Rejected).messages.should eq([Items::RegisterItem::NAME_MESSAGE])
    end
  end

  it "rejects a tag the ledger has" do
    Items::RegisterItem.new("PC-3", "Laptop", true).call.as(Shomen::Rejected).messages.should eq(["PC-3 is already registered"])
  end
end

describe Items::LendItem do
  it "lends an available item to a trimmed borrower" do
    event = Items::LendItem.new(available("PC-4"), " Ada ").call.as(Array(Shomen::Event))[0].as(Items::ItemLent)
    event.tag.should eq("PC-4")
    event.borrower.should eq("Ada")
  end

  it "rejects an item that is lent" do
    Items::LendItem.new(lent("PC-5", "Ada"), "Grace").call.as(Shomen::Rejected).messages.should eq(["PC-5 is lent to Ada. Record its return first"])
  end

  it "rejects an empty or long borrower" do
    ["", "  ", "B" * 81].each do |borrower|
      Items::LendItem.new(available("PC-6"), borrower).call.as(Shomen::Rejected).messages.should eq([Items::LendItem::BORROWER_MESSAGE])
    end
  end
end

describe Items::ReturnItem do
  it "returns a lent item" do
    Items::ReturnItem.new(lent("PC-7", "Ada")).call.as(Array(Shomen::Event))[0].as(Items::ItemReturned).tag.should eq("PC-7")
  end

  it "rejects an item that is not lent" do
    Items::ReturnItem.new(available("PC-8")).call.as(Shomen::Rejected).messages.should eq(["PC-8 is not lent"])
  end
end
