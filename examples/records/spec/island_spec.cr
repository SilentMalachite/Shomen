require "./spec_helper"
require "../../../spec/support/browser"

describe "Name length island" do
  it "renders the name field and a hidden count inside the island" do
    body = Visitor.new.get(Items::New.path).body
    body.should contain(
      %(<div data-shomen-island="name-length" id="name-field"><label for="name">Name</label>) +
      %(<input id="name" name="name" type="text" value="" maxlength="80">) +
      %(<p id="name-left" aria-live="polite" hidden="hidden"></p></div>)
    )
  end

  it "serves the island module" do
    response = Visitor.new.get("/islands/name-length.js")
    response.status_code.should eq(200)
    response.headers["Content-Type"].should eq("text/javascript; charset=utf-8")
    response.body.should eq(File.read("src/records/name_length.js"))
    Items::NameLengthIsland.path.should eq("/islands/name-length.js")
  end

  if Browser.executable
    it "counts the characters left in the browser" do
      with_live_server do |origin|
        with_browser do |browser|
          browser.visit("#{origin}/items/new")
          result = browser.run(<<-JS)
            const left = await waitFor(() => {
              const line = document.getElementById("name-left");
              return line.hidden ? undefined : line;
            });
            const name = document.getElementById("name");
            name.value = "Laptop";
            name.dispatchEvent(new Event("input"));
            return left.textContent;
            JS
          result.as_s.should eq("74 characters left")
        end
      end
    end
  else
    pending("counts the characters left in Chrome (set SHOMEN_CHROME to a Chrome or Chromium binary)") { }
  end
end
