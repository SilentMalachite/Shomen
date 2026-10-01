require "../spec_helper"

private def text(html : String) : Shomen::Fragment
  ETagRoutes::TextFragment.new(html)
end

describe Shomen::FragmentCache do
  it "renders a key once and returns the same HTML after" do
    cache = Shomen::FragmentCache.new
    calls = 0
    2.times do
      cache.fetch("k", "t") { calls += 1; text("<p>x</p>") }.to_html.should eq("<p>x</p>")
    end
    calls.should eq(1)
  end

  it "renders each key apart" do
    cache = Shomen::FragmentCache.new
    cache.fetch("a", "t") { text("a") }.to_html.should eq("a")
    cache.fetch("b", "t") { text("b") }.to_html.should eq("b")
  end

  it "raises for a fragment that contains the CSRF token, and keeps nothing" do
    cache = Shomen::FragmentCache.new
    expect_raises(ArgumentError, "contains the CSRF token") do
      cache.fetch("k", "secret") { text(%(<input value="secret">)) }
    end
    cache.fetch("k", "secret") { text("safe") }.to_html.should eq("safe")
  end

  it "does not look for an empty token" do
    Shomen::FragmentCache.new.fetch("k", "") { text("x") }.to_html.should eq("x")
  end

  it "drops the fragment used least recently once the bytes pass the limit" do
    # Each entry is a 1-byte key and 9 bytes of HTML: two fit in 25 bytes.
    cache = Shomen::FragmentCache.new(max_bytes: 25)
    cache.fetch("a", "t") { text("123456789") }
    cache.fetch("b", "t") { text("123456789") }
    cache.fetch("a", "t") { raise "a was dropped" }
    cache.fetch("c", "t") { text("123456789") }
    cache.fetch("a", "t") { raise "a was dropped" }
    rendered = false
    cache.fetch("b", "t") { rendered = true; text("123456789") }
    rendered.should be_true
  end

  it "keeps no fragment larger than the limit" do
    cache = Shomen::FragmentCache.new(max_bytes: 10)
    calls = 0
    2.times { cache.fetch("big", "t") { calls += 1; text("x" * 20) } }
    calls.should eq(2)
  end

  it "takes only a positive limit" do
    expect_raises(ArgumentError, "max_bytes must be positive") { Shomen::FragmentCache.new(max_bytes: 0) }
  end
end

describe "Shomen::Route#cached" do
  it "keeps values apart by their type and length, and reads every integer alike" do
    cache = Shomen::FragmentCache.new
    route = ETagRoutes::CachedPage.new
    calls = 0
    route.cached(cache, "n", "a", "bc") { calls += 1; text("1") }
    route.cached(cache, "n", "ab", "c") { calls += 1; text("2") }
    route.cached(cache, "n", "1") { calls += 1; text("3") }
    route.cached(cache, "n", 1) { calls += 1; text("4") }
    route.cached(cache, "m", 1_i64) { calls += 1; text("5") }
    calls.should eq(5)
    route.cached(cache, "n", 1_i64) { raise "1 and 1_i64 are one key" }.to_html.should eq("4")
    route.cached(cache, "n", "a", "bc") { raise "not cached" }.to_html.should eq("1")
  end

  it "raises for a fragment that contains the route's CSRF token" do
    route = ETagRoutes::CachedPage.new
    route.csrf_token = "tok"
    expect_raises(ArgumentError, "contains the CSRF token") do
      route.cached(Shomen::FragmentCache.new, "n") { text("tok") }
    end
  end
end

describe "Shomen::Route#cached at compile time" do
  it "fails to compile a key value that is not String, Int32, or Int64" do
    status, output = crystal_build_fixture("spec/fixtures/cached_bad_key.cr")
    status.should_not eq(0)
    output.should contain("cached takes String, Int32, or Int64 key values, got Symbol")
  end
end

describe "Shomen::Server and cached fragments" do
  it "embeds and sends a cached fragment, rendering it once" do
    server = Shomen::Server.new
    ETagRoutes::CALLS.clear
    document = call_with(server, "GET", "/phase7/cached/fc1")
    document.status_code.should eq(200)
    document.body.should contain(%(<div id="note"><p>fc1</p></div>))
    fragment = call_with(server, "GET", "/phase7/cached/fc1", headers: HTTP::Headers{Shomen::Route::TARGET_HEADER => "note"})
    fragment.body.should eq(%(<div id="note"><p>fc1</p></div>))
    ETagRoutes::CALLS.should eq(["render"])
  end

  it "answers 500 when a route caches a fragment with the CSRF token" do
    call_with(Shomen::Server.new, "GET", "/phase7/cached-token").status_code.should eq(500)
  end
end
