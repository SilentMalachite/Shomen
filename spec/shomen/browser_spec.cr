require "../spec_helper"

describe Browser do
  if Browser.executable
    it "loads a page served by Shomen and evaluates a script" do
      with_live_server do |origin|
        with_browser do |browser|
          browser.visit("#{origin}/phase1/home")
          browser.evaluate("document.querySelector('h1').textContent").as_s.should eq("Hello")
          browser.evaluate("new Promise((resolve) => resolve(6 * 7))").as_i.should eq(42)
        end
      end
    end

    it "raises when a script throws" do
      with_browser do |browser|
        expect_raises(Exception, /script failed/) do
          browser.evaluate("(() => { throw new Error('boom'); })()")
        end
      end
    end

    it "runs a script before the scripts of each page it loads" do
      with_live_server do |origin|
        with_browser do |browser|
          browser.before_load("window.shomenEarly = document.readyState;")
          browser.visit("#{origin}/phase1/home")
          browser.evaluate("window.shomenEarly").as_s.should eq("loading")
        end
      end
    end

    it "runs a body where waitFor returns at once when the check already holds" do
      with_browser do |browser|
        browser.run("return await waitFor(() => 6 * 7);").as_i.should eq(42)
      end
    end
  else
    pending("drives Chrome (set SHOMEN_CHROME to a Chrome or Chromium binary)") { }
  end

  # Chrome's first start on a cold machine can take far longer than the
  # starts after it (docs/decisions/20261003-chrome-start-limit.md).
  it "gives Chrome longer to start than one DevTools operation" do
    Browser::START.should be > Browser::LIMIT
  end

  it "reads the address Chrome prints when it listens" do
    error = IO::Memory.new("starting\nDevTools listening on ws://127.0.0.1:9333/devtools/browser/x\n")
    Browser.endpoint(error).should eq({"127.0.0.1", 9333})
  end

  it "fails when Chrome does not listen within the start limit" do
    reader, writer = IO.pipe
    begin
      expect_raises(Exception, "Chrome did not listen within") do
        Browser.endpoint(reader, within: 50.milliseconds)
      end
    ensure
      writer.close
      reader.close
    end
  end
end
