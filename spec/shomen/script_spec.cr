require "../spec_helper"

# waitFor(check) resolves with check()'s first value other than
# undefined, looking again after every change to the document.
private def wait_for_js : String
  <<-JS
    const waitFor = (check) => new Promise((resolve) => {
      const observer = new MutationObserver(() => {
        const value = check();
        if (value !== undefined) {
          observer.disconnect();
          resolve(value);
        }
      });
      observer.observe(document, {subtree: true, childList: true, attributes: true, characterData: true});
    });
    JS
end

private def run_js(browser : Browser, body : String) : JSON::Any
  browser.evaluate("(async () => {\n#{wait_for_js}\n#{body}\n})()")
end

private def on_page(& : Browser, String ->) : Nil
  BrowserRoutes::RECEIVED.clear
  with_live_server do |origin|
    with_browser do |browser|
      browser.visit("#{origin}/phase4/browser")
      yield browser, origin
    end
  end
end

describe "shomen.js" do
  if Browser.executable
    it "replaces only the element named by data-shomen-get" do
      on_page do |browser, _|
        result = run_js(browser, <<-JS)
          document.getElementById("outside").shomenMarker = "kept";
          const done = waitFor(() => document.getElementById("slot").textContent.includes("loaded") ? true : undefined);
          document.getElementById("load").click();
          await done;
          return {
            marker: document.getElementById("outside").shomenMarker,
            slot: document.getElementById("slot").outerHTML,
            path: location.pathname,
          };
          JS
        result["marker"].as_s.should eq("kept")
        result["slot"].as_s.should eq("<div id=\"slot\"><p>loaded slot</p></div>")
        result["path"].as_s.should eq("/phase4/browser")
        BrowserRoutes::RECEIVED.should eq(["GET /phase4/browser/slot slot"])
      end
    end

    it "replaces only the form on 422 and keeps the focus" do
      on_page do |browser, _|
        result = run_js(browser, <<-JS)
          document.getElementById("outside").shomenMarker = "kept";
          document.getElementById("name").value = "A";
          const save = document.getElementById("save");
          save.focus();
          const done = waitFor(() => document.querySelector("#box [role=alert]") ? true : undefined);
          save.click();
          await done;
          return {
            marker: document.getElementById("outside").shomenMarker,
            alert: document.querySelector("#box [role=alert]").textContent,
            value: document.getElementById("name").value,
            focused: document.activeElement.id,
            slot: document.getElementById("slot").textContent,
            busy: document.getElementById("box").hasAttribute("aria-busy"),
            path: location.pathname,
          };
          JS
        result["marker"].as_s.should eq("kept")
        result["alert"].as_s.should eq("Name is too short")
        result["value"].as_s.should eq("A")
        result["focused"].as_s.should eq("save")
        result["slot"].as_s.should eq("Load")
        result["busy"].as_bool.should be_false
        result["path"].as_s.should eq("/phase4/browser")
        BrowserRoutes::RECEIVED.should eq(["POST /phase4/browser/form box"])
      end
    end

    it "loads the new page after a redirect" do
      on_page do |browser, _|
        run_js(browser, <<-JS)
          document.getElementById("name").value = "Ada";
          document.getElementById("save").click();
          JS
        browser.wait_for("Page.loadEventFired")
        browser.evaluate("location.pathname").as_s.should eq("/phase4/browser/plain")
        browser.evaluate("document.title").as_s.should eq("Plain")
        BrowserRoutes::RECEIVED.first.should eq("POST /phase4/browser/form box")
      end
    end

    it "shows a response without the element as the whole page after a POST" do
      on_page do |browser, _|
        result = run_js(browser, <<-JS)
          const done = waitFor(() => document.title === "Conflict" ? true : undefined);
          document.getElementById("clash").click();
          await done;
          return {path: location.pathname, text: document.body.textContent, slots: document.querySelectorAll("#slot").length};
          JS
        result["path"].as_s.should eq("/phase4/browser")
        result["text"].as_s.should contain(Shomen::Server::CONFLICT_DETAIL)
        result["slots"].as_i.should eq(0)
        BrowserRoutes::RECEIVED.should eq(["POST /phase4/browser/conflict slot"])
      end
    end

    it "loads the URL when a GET response lacks the element" do
      on_page do |browser, _|
        run_js(browser, %(document.getElementById("plain").click();))
        browser.wait_for("Page.loadEventFired")
        browser.evaluate("location.pathname").as_s.should eq("/phase4/browser/plain")
        BrowserRoutes::RECEIVED.should eq(["GET /phase4/browser/plain slot", "GET /phase4/browser/plain -"])
      end
    end

    it "leaves cross-origin, modified, and new-window clicks to the browser" do
      on_page do |browser, origin|
        far = origin.sub("127.0.0.1", "localhost")
        result = run_js(browser, <<-JS)
          const prevented = (element, init) => {
            let seen = null;
            window.addEventListener("click", (event) => { seen = event.defaultPrevented; event.preventDefault(); }, {once: true});
            element.dispatchEvent(new MouseEvent("click", {bubbles: true, cancelable: true, ...init}));
            return seen;
          };
          const farLink = document.createElement("a");
          farLink.href = "#{far}/phase4/browser/slot";
          farLink.setAttribute("data-shomen-get", "slot");
          farLink.textContent = "Far";
          document.body.append(farLink);
          const load = document.getElementById("load");
          const blank = load.cloneNode(true);
          blank.id = "blank";
          blank.target = "_blank";
          document.body.append(blank);
          return [
            prevented(farLink, {}),
            prevented(load, {ctrlKey: true}),
            prevented(load, {metaKey: true}),
            prevented(load, {button: 1}),
            prevented(blank, {}),
          ];
          JS
        result.as_a.map(&.as_bool).should eq([false, false, false, false, false])
        BrowserRoutes::RECEIVED.should be_empty
      end
    end

    it "sends one request when a form is submitted twice before the answer" do
      on_page do |browser, _|
        result = run_js(browser, <<-JS)
          document.getElementById("name").value = "A";
          const form = document.getElementById("box-form");
          const done = waitFor(() => document.querySelector("#box [role=alert]") ? true : undefined);
          form.requestSubmit();
          form.requestSubmit();
          await done;
          return document.querySelectorAll("#box [role=alert]").length;
          JS
        result.as_i.should eq(1)
        BrowserRoutes::RECEIVED.should eq(["POST /phase4/browser/form box"])
      end
    end
  else
    pending("runs in Chrome (set SHOMEN_CHROME to a Chrome or Chromium binary)") { }
  end
end
