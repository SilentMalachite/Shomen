require "./spec_helper"

describe "Registering an item" do
  it "builds paths from the route declarations" do
    Items::Index.path.should eq("/items")
    Items::New.path.should eq("/items/new")
    Items::Create.path.should eq("/items")
    Items::Show.path(tag: "PC-1").should eq("/items/PC-1")
  end

  it "registers an item and shows it on the next page of the session" do
    visitor = Visitor.new
    response = register(visitor, "A-1", " Laptop ")
    response.status_code.should eq(303)
    response.headers["Location"].should eq("/items/A-1")
    visitor.cookies["shomen_append"]?.should_not be_nil
    page = visitor.get("/items/A-1")
    page.status_code.should eq(200)
    page.body.should contain("<h1>A-1 Laptop</h1>")
    page.body.should contain(%(<p id="status">Available</p>))
    visitor.get("/items").body.should contain(%(<li><a href="/items/A-1">A-1</a> Laptop: available</li>))
  end

  it "records one item_registered event at version 1" do
    register(Visitor.new, "A-2", "Projector").status_code.should eq(303)
    events = events_of("A-2")
    events.map(&.event.event_type).should eq(["item_registered"])
    events.map(&.version).should eq([1_i64])
  end

  it "refuses a form without the CSRF token" do
    visitor = Visitor.new
    visitor.get(Items::New.path)
    visitor.post(Items::Create.path, {"tag" => "A-3", "name" => "Laptop"}).status_code.should eq(403)
    events_of("A-3").should be_empty
  end

  it "redisplays a tag a path cannot carry with 422" do
    ["a-4", "A/4", "A?4", "..", "-A4"].each do |tag|
      response = register(Visitor.new, tag, "Laptop")
      response.status_code.should eq(422)
      response.body.should contain(Items::RegisterItem::TAG_MESSAGE)
      response.body.should contain(%(value="#{Shomen::HTML.escape(tag)}"))
    end
  end

  it "redisplays a tag registered before with 422 and records nothing more" do
    visitor = Visitor.new
    register(visitor, "A-5", "Laptop").status_code.should eq(303)
    response = register(visitor, "A-5", "Camera")
    response.status_code.should eq(422)
    response.body.should contain("A-5 is already registered")
    events_of("A-5").size.should eq(1)
  end

  it "escapes the name it shows" do
    visitor = Visitor.new
    register(visitor, "A-6", "<b>Lamp</b>")
    visitor.get("/items/A-6").body.should contain("<h1>A-6 &lt;b&gt;Lamp&lt;/b&gt;</h1>")
  end

  it "answers 404 for a tag the ledger does not have" do
    Visitor.new.get("/items/NONE").status_code.should eq(404)
  end
end
