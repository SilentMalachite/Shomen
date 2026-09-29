require "../spec_helper"
require "yaml"

private def with_sse_routes(& : Shomen::Store ->) : Nil
  with_store do |store|
    SSERoutes.store = store
    SSERoutes::TARGET[0] = "count"
    SSERoutes.drain_rendered
    begin
      yield store
    ensure
      SSERoutes.store = nil
    end
  end
end

describe Shomen::SSE do
  it "puts every line of the HTML in its own data line" do
    Shomen::SSE.message(%(<p>a</p>)).should eq("data: <p>a</p>\n\n")
    Shomen::SSE.message("<p>a\r\nb\rc\nd</p>").should eq("data: <p>a\ndata: b\ndata: c\ndata: d</p>\n\n")
    Shomen::SSE.message("<p>x\n\nevent: boom\ndata: y</p>").should eq(
      "data: <p>x\ndata: \ndata: event: boom\ndata: data: y</p>\n\n"
    )
  end

  it "answers with an event stream that starts with the current fragment" do
    with_sse_routes do
      with_sse_client(SSERoutes::Live.path) do |client|
        client.status.should eq(200)
        client.headers["Content-Type"].should eq("text/event-stream")
        client.headers["Cache-Control"].should eq("no-store")
        client.headers["X-Content-Type-Options"].should eq("nosniff")
        client.next_message.should eq(%(<p id="count">0</p>))
      end
    end
  end

  it "sends the fragment again after this process appends" do
    with_sse_routes do |store|
      with_sse_client(SSERoutes::Live.path) do |client|
        client.next_message.should eq(%(<p id="count">0</p>))
        store.append("sse-1", 0_i64, note("one"))
        client.next_message.should eq(%(<p id="count">1</p>))
      end
    end
  end

  it "sends nothing when an append leaves the fragment as it was" do
    with_sse_routes do |store|
      with_sse_client(SSERoutes::Live.path) do |client|
        client.next_message.should eq(%(<p id="count">0</p>))
        SSERoutes.next_render.should eq("count")
        store.append("sse-1", 0_i64, [SpecEvents::Renamed.new("x")] of Shomen::Event)
        SSERoutes.next_render.should eq("count")
        store.append("sse-1", 1_i64, note("one"))
        client.next_message.should eq(%(<p id="count">1</p>))
      end
    end
  end

  it "does not lose an append made while the fragment renders" do
    with_sse_routes do
      with_sse_client(SSERoutes::Racing.path) do |client|
        client.next_message.should eq(%(<p id="count">0</p>))
        client.next_message.should eq(%(<p id="count">1</p>))
      end
    end
  end

  it "writes a comment when it sent nothing for a heartbeat" do
    with_sse_routes do
      with_sse_client(SSERoutes::Live.path) do |client|
        client.next_message.should eq(%(<p id="count">0</p>))
        client.next_block.should eq(":")
      end
    end
  end

  it "ends when the client leaves" do
    with_sse_routes do
      client = SSEClient.new(Shomen::Server.new, SSERoutes::Live.path)
      client.next_message.should eq(%(<p id="count">0</p>))
      client.close
      client.wait_finished
    end
  end

  it "answers an error in the first render with the error document" do
    with_sse_routes do
      response = call_with(Shomen::Server.new, "GET", SSERoutes::Missing.path)
      response.status_code.should eq(404)
      response.headers["Content-Type"].should eq("text/html; charset=utf-8")
      response.body.should contain("Not found")
    end
  end

  it "adds no shard, so an application without SSE gains no dependency" do
    YAML.parse(File.read("shard.yml"))["dependencies"].as_h.keys.map(&.as_s).should eq(["sqlite3", "db"])
    locked = YAML.parse(File.read("examples/hello/shard.lock"))["shards"].as_h.keys.map(&.as_s)
    locked.sort.should eq(["db", "shomen", "sqlite3"])
  end
end
