require "./spec_helper"
require "../../../spec/support/sse_client"

describe "The live item list" do
  it "sends the list again after an item is registered" do
    client = SSEClient.new(Shomen::Server.new, Items::Live.path)
    begin
      client.status.should eq(200)
      client.headers["Content-Type"].should eq("text/event-stream")
      client.next_message.should start_with(%(<div id="item-list">))
      register(Visitor.new, "S-1", "<b>Camera</b>").status_code.should eq(303)
      message = client.next_message
      until message.includes?("S-1")
        message = client.next_message
      end
      message.should contain(%(<li><a href="/items/S-1">S-1</a> &lt;b&gt;Camera&lt;/b&gt;: available</li>))
    ensure
      client.close
      # The stream ends when it next writes, and the next append makes it
      # write well before its heartbeat.
      register(Visitor.new, "S-2", "Tripod")
      client.wait_finished
    end
  end
end
