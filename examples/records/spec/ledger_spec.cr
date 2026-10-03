require "./spec_helper"

private AT = Time.utc(2026, 10, 3, 9, 0, 0)

private def append(tag : String, version : Int64, event : Shomen::Event) : Int64
  Records::STORE.append(Items.stream(tag), version, [event] of Shomen::Event)
end

describe Items::Ledger do
  it "keeps a row for a registered item" do
    seen = append("C-1", 0_i64, Items::ItemRegistered.new("C-1", "Laptop", AT))
    Items.find("C-1", seen).should eq(Items::Item.new("C-1", "Laptop", nil, 1_i64, seen))
    Items.find_with_loans("C-1", seen).should eq({Items::Item.new("C-1", "Laptop", nil, 1_i64, seen), [] of Items::Loan})
  end

  it "keeps the borrower and a loan row for a lend" do
    append("C-2", 0_i64, Items::ItemRegistered.new("C-2", "Laptop", AT))
    seen = append("C-2", 1_i64, Items::ItemLent.new("C-2", "Ada", AT))
    item = Items.find("C-2", seen)
    item.should eq(Items::Item.new("C-2", "Laptop", "Ada", 2_i64, seen))
    item.try(&.lent?).should be_true
    Items.find_with_loans("C-2", seen).try(&.[1]).should eq([Items::Loan.new("Ada", "2026-10-03T09:00:00Z", nil)])
  end

  it "frees the item and closes its loan on a return" do
    append("C-3", 0_i64, Items::ItemRegistered.new("C-3", "Laptop", AT))
    append("C-3", 1_i64, Items::ItemLent.new("C-3", "Ada", AT))
    seen = append("C-3", 2_i64, Items::ItemReturned.new("C-3", AT + 1.hour))
    Items.find("C-3", seen).should eq(Items::Item.new("C-3", "Laptop", nil, 3_i64, seen))
    Items.find_with_loans("C-3", seen).try(&.[1]).should eq([Items::Loan.new("Ada", "2026-10-03T09:00:00Z", "2026-10-03T10:00:00Z")])
  end

  it "keeps loans newest first next to the item they belong to" do
    append("C-7", 0_i64, Items::ItemRegistered.new("C-7", "Laptop", AT))
    append("C-7", 1_i64, Items::ItemLent.new("C-7", "Ada", AT))
    append("C-7", 2_i64, Items::ItemReturned.new("C-7", AT + 1.hour))
    seen = append("C-7", 3_i64, Items::ItemLent.new("C-7", "Grace", AT + 2.hours))
    item, loans = Items.find_with_loans("C-7", seen).not_nil!
    item.should eq(Items::Item.new("C-7", "Laptop", "Grace", 4_i64, seen))
    loans.map(&.borrower).should eq(["Grace", "Ada"])
  end

  it "lists the items in tag order and changes last_change with each event" do
    first = append("C-5", 0_i64, Items::ItemRegistered.new("C-5", "Camera", AT))
    Items.last_change(Items.all(first)).should eq(first)
    seen = append("C-4", 0_i64, Items::ItemRegistered.new("C-4", "Tripod", AT))
    tags = Items.all(seen).map(&.tag).select(&.in?("C-4", "C-5"))
    tags.should eq(["C-4", "C-5"])
    Items.last_change(Items.all(seen)).should eq(seen)
  end

  it "has a checkpoint at least the id a read waited for" do
    seen = append("C-6", 0_i64, Items::ItemRegistered.new("C-6", "Laptop", AT))
    Items.find("C-6", seen)
    Records::LEDGER.checkpoint.should be >= seen
  end

  it "finds nothing for a tag it has no row for" do
    Items.find("NONE", 0_i64).should be_nil
    Items.find_with_loans("NONE", 0_i64).should be_nil
  end

  it "has no last change without items" do
    Items.last_change([] of Items::Item).should eq(0_i64)
  end
end
