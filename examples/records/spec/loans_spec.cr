require "./spec_helper"

describe "Lending and returning" do
  it "lends an available item and shows the loan" do
    visitor = Visitor.new
    register(visitor, "L-1", "Laptop")
    response = lend(visitor, "L-1", " Ada ")
    response.status_code.should eq(303)
    response.headers["Location"].should eq("/items/L-1")
    page = visitor.get("/items/L-1").body
    page.should contain(%(<p id="status">Lent to Ada</p>))
    page.should contain(%(<button type="submit" id="return-submit">Record the return</button>))
    page.should match(/<li>Ada, lent [^,<]+, not returned<\/li>/)
    events_of("L-1").map(&.event.event_type).should eq(["item_registered", "item_lent"])
  end

  it "records the return and offers the item again" do
    visitor = Visitor.new
    register(visitor, "L-2", "Laptop")
    lend(visitor, "L-2", "Ada")
    give_back(visitor, "L-2").status_code.should eq(303)
    page = visitor.get("/items/L-2").body
    page.should contain(%(<p id="status">Available</p>))
    page.should match(/<li>Ada, lent [^,<]+, returned [^<]+<\/li>/)
    events_of("L-2").map(&.version).should eq([1_i64, 2_i64, 3_i64])
  end

  it "answers a fragment of the loan form with 422 when the borrower is empty" do
    visitor = Visitor.new
    register(visitor, "L-3", "Laptop")
    response = lend(visitor, "L-3", "  ", target: "loan-form")
    response.status_code.should eq(422)
    response.body.should start_with(%(<div id="loan-form"><p role="alert">#{Items::LendItem::BORROWER_MESSAGE}</p>))
    response.body.should_not contain("<html")
    events_of("L-3").size.should eq(1)
  end

  it "redirects a valid lend sent with or without shomen.js" do
    visitor = Visitor.new
    register(visitor, "L-4", "Laptop")
    lend(visitor, "L-4", "Ada", target: "loan-form").headers["Location"].should eq("/items/L-4")
    give_back(visitor, "L-4").headers["Location"].should eq("/items/L-4")
  end

  it "answers a form opened before another lend with 409, shows the item now, and records nothing" do
    visitor = Visitor.new
    register(visitor, "L-5", "Laptop")
    page = visitor.get("/items/L-5").body
    lend(visitor, "L-5", "Ada").status_code.should eq(303)
    stale = {"_csrf" => Visitor.token(page), "version" => Visitor.version(page), "borrower" => "Grace"}
    response = visitor.post(Items::Lend.path(tag: "L-5"), stale)
    response.status_code.should eq(409)
    response.body.should contain("L-5 changed after this form was shown. Check it and try again.")
    response.body.should contain(%(<p id="status">Lent to Ada</p>))
    events_of("L-5").size.should eq(2)
  end

  it "answers a return sent from a form that offered the item with 409" do
    visitor = Visitor.new
    register(visitor, "L-6", "Laptop")
    lend(visitor, "L-6", "Ada")
    page = visitor.get("/items/L-6").body
    give_back(visitor, "L-6")
    lend(visitor, "L-6", "Grace")
    form = {"_csrf" => Visitor.token(page), "version" => Visitor.version(page)}
    visitor.post(Items::Return.path(tag: "L-6"), form, "loan-form").status_code.should eq(409)
    visitor.get("/items/L-6").body.should contain(%(<p id="status">Lent to Grace</p>))
  end

  it "answers 404 for a lend of a tag the ledger does not have" do
    visitor = Visitor.new
    token = Visitor.token(visitor.get(Items::New.path).body)
    form = {"_csrf" => token, "version" => "0", "borrower" => "Ada"}
    visitor.post(Items::Lend.path(tag: "NONE"), form).status_code.should eq(404)
  end

  it "escapes the borrower" do
    visitor = Visitor.new
    register(visitor, "L-7", "Laptop")
    lend(visitor, "L-7", "<i>Ada</i>")
    visitor.get("/items/L-7").body.should contain(%(<p id="status">Lent to &lt;i&gt;Ada&lt;/i&gt;</p>))
  end
end

describe "The loan history" do
  it "comes from the fragment cache until the item changes" do
    visitor = Visitor.new
    register(visitor, "H-1", "Laptop")
    lend(visitor, "H-1", "Ada")
    visitor.get("/items/H-1").body.should contain("<li>Ada, lent ")
    # A change the ledger did not make: the cached history does not show it.
    Records::LEDGER.read do |connection|
      connection.exec("UPDATE records_loans SET borrower = $1 WHERE tag = $2", "Changed", "H-1")
    end
    visitor.get("/items/H-1").body.should_not contain("<li>Changed, lent ")
    give_back(visitor, "H-1")
    visitor.get("/items/H-1").body.should contain("<li>Changed, lent ")
  end
end
