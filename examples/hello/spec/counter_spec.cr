require "./spec_helper"
require "http/client"
require "../../../spec/support/browser"

private def get(path : String) : HTTP::Client::Response
  io = IO::Memory.new
  response = HTTP::Server::Response.new(io)
  Shomen::Server.new.call(HTTP::Server::Context.new(HTTP::Request.new("GET", path), response))
  response.close
  HTTP::Client::Response.from_io(IO::Memory.new(io.to_s))
end

describe "Counter island" do
  it "renders the count and a hidden button inside the island" do
    response = get("/counter")
    response.status_code.should eq(200)
    response.body.should contain(%(<script src="/shomen.js" defer></script>))
    response.body.should contain(
      %(<div data-shomen-island="counter" id="counter"><p id="counter-value" aria-live="polite">0</p>) +
      %(<button type="button" id="counter-add" hidden="hidden">Add one</button></div>)
    )
  end

  it "serves the island module" do
    response = get("/islands/counter.js")
    response.status_code.should eq(200)
    response.headers["Content-Type"].should eq("text/javascript; charset=utf-8")
    response.body.should eq(File.read("src/counter.js"))
    Counter::CounterIsland.path.should eq("/islands/counter.js")
  end

  if Browser.executable
    it "counts clicks in the browser" do
      with_live_server do |origin|
        with_browser do |browser|
          browser.visit("#{origin}/counter")
          result = browser.run(<<-JS)
            const add = await waitFor(() => {
              const button = document.getElementById("counter-add");
              return button.hidden ? undefined : button;
            });
            add.click();
            add.click();
            add.click();
            return document.getElementById("counter-value").textContent;
            JS
          result.as_s.should eq("3")
        end
      end
    end
  else
    pending("counts clicks in Chrome (set SHOMEN_CHROME to a Chrome or Chromium binary)") { }
  end
end
