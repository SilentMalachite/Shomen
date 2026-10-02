require "./spec_helper"

describe "The item list" do
  it "answers 304 to the validator it sent until an item changes" do
    visitor = Visitor.new
    # The session now remembers the latest append, so the ledger has every
    # event before it, and the list stays as it is until this spec appends.
    register(visitor, "X-1", "Laptop")
    first = visitor.get("/items")
    first.status_code.should eq(200)
    etag = first.headers["ETag"]
    etag.should start_with(%(W/"))
    first.headers["Cache-Control"].should eq("private, no-cache")

    again = visitor.get("/items", HTTP::Headers{"If-None-Match" => etag})
    again.status_code.should eq(304)
    again.body.should be_empty

    lend(visitor, "X-1", "Ada")
    changed = visitor.get("/items", HTTP::Headers{"If-None-Match" => etag})
    changed.status_code.should eq(200)
    changed.headers["ETag"].should_not eq(etag)
    changed.body.should contain(%(<a href="/items/X-1">X-1</a> Laptop: lent to Ada</li>))
  end

  it "puts the list in the element the stream replaces" do
    body = Visitor.new.get("/items").body
    body.should contain(%(<div id="items-live" data-shomen-sse="/items/live"><div id="item-list">))
    body.should contain(%(<script src="/shomen.js" defer></script>))
  end
end
