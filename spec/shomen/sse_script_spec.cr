require "../spec_helper"

private def on_live_page(& : Browser, Shomen::Store ->) : Nil
  with_store do |store|
    SSERoutes.store = store
    SSERoutes::TARGET[0] = "count"
    SSERoutes.drain_rendered
    begin
      with_live_server do |origin|
        with_browser do |browser|
          browser.before_load(PAGE_SPY)
          browser.visit("#{origin}#{SSERoutes::Page.path}")
          yield browser, store
        end
      end
    ensure
      SSERoutes.store = nil
    end
  end
end

# Waits until the stream at index has its headers. Its first message is
# on the way, and an append from now on reaches it.
private def wait_open(browser : Browser, index : Int32) : Nil
  browser.run(<<-JS)
    const source = await waitFor(() => window.shomenSeen.sources[#{index}]);
    if (source.readyState !== EventSource.OPEN) {
      await new Promise((resolve) => source.addEventListener("open", resolve, {once: true}));
    }
    return true;
    JS
end

describe "shomen.js with SSE" do
  if Browser.executable
    it "replaces the element a message names inside the holder" do
      on_live_page do |browser, store|
        wait_open(browser, 0)
        browser.evaluate(%(document.getElementById("outside").shomenMarker = "kept"; 0))
        store.append("live-1", 0_i64, note("one"))
        result = browser.run(<<-JS)
          await waitFor(() => document.getElementById("count").textContent === "1" ? true : undefined);
          return {
            marker: document.getElementById("outside").shomenMarker,
            holder: document.getElementById("live").outerHTML,
            path: location.pathname,
          };
          JS
        result["marker"].as_s.should eq("kept")
        result["holder"].as_s.should eq(%(<div id="live" data-shomen-sse="/phase5/live"><p id="count">1</p></div>))
        result["path"].as_s.should eq("/phase5/live-page")
      end
    end

    it "drops a message whose element is outside the holder" do
      on_live_page do |browser, store|
        wait_open(browser, 0)
        SSERoutes.next_render.should eq("count")
        SSERoutes::TARGET[0] = "outside"
        store.append("live-1", 0_i64, note("one"))
        SSERoutes.next_render.should eq("outside")
        SSERoutes::TARGET[0] = "count"
        store.append("live-1", 1_i64, note("two"))
        result = browser.run(<<-JS)
          await waitFor(() => document.getElementById("count").textContent === "2" ? true : undefined);
          return document.getElementById("outside").outerHTML;
          JS
        result.as_s.should eq(%(<p id="outside">outside</p>))
      end
    end

    it "closes the stream of a holder a replacement removed and follows the new one" do
      on_live_page do |browser, store|
        wait_open(browser, 0)
        result = browser.run(<<-JS)
          const old = document.getElementById("live");
          const done = waitFor(() => document.getElementById("live") !== old ? true : undefined);
          document.getElementById("swap").click();
          await done;
          return {count: window.shomenSeen.sources.length, first: window.shomenSeen.sources[0].readyState};
          JS
        result["count"].as_i.should eq(2)
        result["first"].as_i.should eq(2)
        wait_open(browser, 1)
        store.append("live-1", 0_i64, note("one"))
        done = browser.run(%(return await waitFor(() => document.getElementById("count").textContent === "1" ? true : undefined);))
        done.as_bool.should be_true
      end
    end

    it "opens no stream for a holder on another origin" do
      on_live_page do |browser, _|
        paths = browser.evaluate("window.shomenSeen.sources.map((source) => new URL(source.url).pathname)")
        paths.as_a.map(&.as_s).should eq(["/phase5/live"])
      end
    end

    it "closes a stream a redirect took to another origin and drops its message" do
      with_store do |store|
        SSERoutes.store = store
        begin
          with_live_server do |origin|
            SSERoutes::FAR[0] = origin.sub("127.0.0.1", "localhost") + SSERoutes::Far.path
            with_browser do |browser|
              browser.before_load(PAGE_SPY)
              browser.visit("#{origin}#{SSERoutes::DetourPage.path}")
              result = browser.run(<<-JS)
                const source = await waitFor(() => window.shomenSeen.sources[0]);
                const text = () => document.getElementById("far-count").textContent;
                // Closing changes nothing on the page, so this looks again every 20 ms.
                await new Promise((resolve) => {
                  const look = () => source.readyState === EventSource.CLOSED || text() !== "near" ? resolve() : setTimeout(look, 20);
                  look();
                });
                return text();
                JS
              result.as_s.should eq("near")
            end
          end
        ensure
          SSERoutes.store = nil
        end
      end
    end

    it "opens no stream on a page without data-shomen-sse" do
      with_live_server do |origin|
        with_browser do |browser|
          browser.before_load(PAGE_SPY)
          browser.visit("#{origin}/phase4/browser")
          result = browser.evaluate(<<-JS)
            ({
              sources: window.shomenSeen.sources.length,
              clicks: window.shomenSeen.listeners.filter(({target, type}) => target === document && type === "click").length,
            })
            JS
          result["sources"].as_i.should eq(0)
          result["clicks"].as_i.should eq(1)
        end
      end
    end
  else
    pending("runs in Chrome (set SHOMEN_CHROME to a Chrome or Chromium binary)") { }
  end
end
