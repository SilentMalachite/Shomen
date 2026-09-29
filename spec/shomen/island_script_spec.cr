require "../spec_helper"

private def on_islands_page(& : Browser, Shomen::Store ->) : Nil
  with_store do |store|
    SSERoutes.store = store
    SSERoutes::TARGET[0] = "count"
    begin
      with_live_server do |origin|
        with_browser do |browser|
          browser.before_load(PAGE_SPY)
          browser.visit("#{origin}#{IslandRoutes::Page.path}")
          yield browser, store
        end
      end
    ensure
      SSERoutes.store = nil
    end
  end
end

# A promise that resolves once the module of the island id has shown its button.
private def shown(id : String) : String
  %(waitFor(() => document.getElementById("#{id}-add")?.hidden === false ? true : undefined))
end

describe "shomen.js islands" do
  if Browser.executable
    it "runs the module of an island on its element" do
      on_islands_page do |browser, _|
        result = browser.run(<<-JS)
          await #{shown("first")};
          const add = document.getElementById("first-add");
          add.click();
          add.click();
          return document.getElementById("first-value").textContent;
          JS
        result.as_s.should eq("2")
      end
    end

    it "runs the module of an island a replacement brings, once" do
      on_islands_page do |browser, _|
        result = browser.run(<<-JS)
          await #{shown("first")};
          document.getElementById("more-link").click();
          await #{shown("second")};
          document.getElementById("second-add").click();
          return [document.getElementById("second-value").textContent, document.getElementById("first-value").textContent];
          JS
        result.as_a.map(&.as_s).should eq(["11", "0"])
      end
    end

    # Both names resolve to one module, which runs its callers in order,
    # so the bad island would show its button before the first one does.
    it "loads no module for an island name that is not a plain name" do
      on_islands_page do |browser, _|
        result = browser.run(<<-JS)
          await #{shown("first")};
          return document.getElementById("bad-add").hidden;
          JS
        result.as_bool.should be_true
      end
    end

    it "adds no event listener outside an island" do
      on_islands_page do |browser, store|
        browser.run(<<-JS)
          await #{shown("first")};
          document.getElementById("first-add").click();
          document.getElementById("more-link").click();
          await #{shown("second")};
          return true;
          JS
        store.append("islands-1", 0_i64, note("one"))
        result = browser.run(<<-JS)
          await waitFor(() => document.getElementById("count").textContent === "1" ? true : undefined);
          document.getElementById("first-add").click();
          const where = (target) => {
            if (target === window) return "window";
            if (target === document) return "document";
            if (target instanceof EventSource) return "source";
            if (target instanceof Element) {
              return target.closest("[data-shomen-island]") ? "island" : `outside ${target.localName}#${target.id}`;
            }
            return `other ${target}`;
          };
          const seen = window.shomenSeen.listeners.map(({target, type}) => `${where(target)} ${type}`);
          return {seen: [...new Set(seen)].sort(), first: document.getElementById("first-value").textContent};
          JS
        result["seen"].as_a.map(&.as_s).should eq([
          "document click", "document submit", "island click", "source message", "window pageshow",
        ])
        result["first"].as_s.should eq("2")
      end
    end
  else
    pending("runs in Chrome (set SHOMEN_CHROME to a Chrome or Chromium binary)") { }
  end
end
