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
  else
    pending("drives Chrome (set SHOMEN_CHROME to a Chrome or Chromium binary)") { }
  end
end
