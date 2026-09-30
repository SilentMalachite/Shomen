require "../spec_helper"

# Records each policy violation the page reports in window.cspViolations,
# before any page script runs. The examples read that array.
CSP_SPY = <<-JS
  window.cspViolations = [];
  document.addEventListener("securitypolicyviolation", (event) => {
    window.cspViolations.push(event.effectiveDirective);
  });
  JS

describe "Content-Security-Policy in a browser" do
  if Browser.executable
    it "stops an inline script" do
      with_live_server do |origin|
        with_browser do |browser|
          browser.before_load(CSP_SPY)
          browser.visit("#{origin}#{CSPRoutes::Inline.path}")
          result = browser.run(<<-JS)
            const violations = await waitFor(() => window.cspViolations.length > 0 ? window.cspViolations : undefined);
            return { ran: window.inlineRan === true, violations };
            JS
          result["ran"].as_bool.should be_false
          result["violations"].as_a.map(&.as_s).should contain("script-src-elem")
        end
      end
    end

    it "runs an inline script under a policy the route set" do
      with_live_server do |origin|
        with_browser do |browser|
          browser.before_load(CSP_SPY)
          browser.visit("#{origin}#{CSPRoutes::Own.path}")
          result = browser.run("return { ran: window.inlineRan === true, violations: window.cspViolations };")
          result["ran"].as_bool.should be_true
          result["violations"].as_a.should be_empty
        end
      end
    end

    it "lets shomen.js run islands, a stream, and a fetch with no violation" do
      on_islands_page(CSP_SPY) do |browser, store|
        # Islands (import()) and the fetch replacement.
        browser.run(<<-JS)
          await waitFor(() => document.getElementById("first-add")?.hidden === false ? true : undefined);
          document.getElementById("more-link").click();
          await waitFor(() => document.getElementById("second-add")?.hidden === false ? true : undefined);
          return true;
          JS
        # The stream (EventSource): an append shows up on the page.
        store.append("csp-1", 0_i64, note("one"))
        result = browser.run(<<-JS)
          await waitFor(() => document.getElementById("count").textContent === "1" ? true : undefined);
          return window.cspViolations;
          JS
        result.as_a.should be_empty
      end
    end
  end
end
