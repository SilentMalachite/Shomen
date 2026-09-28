require "../spec_helper"

private class Page < Shomen::View
  def to_html : String
    html lang: "zh-Hant" do
      head do
        title "say \"hi\""
        meta name: "title", content: "ignored"
      end
      body do
        h1 "Hello"
        p "the word title stays text"
        button type: "submit" do
          text "Go"
        end
        button "Later", type: "button"
        img alt: "", src: "/dot.png"
        img alt: "Logo", src: "/logo.png"
      end
    end
  end
end

describe Shomen::View do
  it "renders one document with lang, title, button, and alt" do
    html = Page.new.to_html
    html.should start_with("<!DOCTYPE html><html lang=\"zh-Hant\">")
    html.should contain("<title>say &quot;hi&quot;</title>")
    html.should contain("<p>the word title stays text</p>")
    html.should contain("<button type=\"submit\">Go</button>")
    html.should contain("<button type=\"button\">Later</button>")
    html.should contain("<img alt=\"\" src=\"/dot.png\">")
    html.should contain("<img alt=\"Logo\" src=\"/logo.png\">")
    html.should end_with("</html>")
    Page.new.to_html.should eq(html)
  end

  it "rejects a document without a title element" do
    status, output = crystal_build_fixture("spec/fixtures/missing_title.cr")
    status.should_not eq(0)
    output.should contain("exactly one title")
  end

  it "rejects two title elements" do
    status, output = crystal_build_fixture("spec/fixtures/two_titles.cr")
    status.should_not eq(0)
    output.should contain("exactly one title")
  end

  it "rejects a document whose only title() is inside a regex literal" do
    status, output = crystal_build_fixture("spec/fixtures/title_only_in_regex.cr")
    status.should_not eq(0)
    output.should contain("exactly one title")
  end

  it "accepts one title element when a regex literal also contains title()" do
    status, output = crystal_build_fixture("spec/fixtures/title_with_regex.cr")
    status.should eq(0)
  end

  it "rejects a button without type" do
    status, output = crystal_build_fixture("spec/fixtures/button_missing_type.cr")
    status.should_not eq(0)
    output.should contain("button requires type")
  end

  it "rejects a button type outside submit, button, and reset" do
    status, output = crystal_build_fixture("spec/fixtures/button_bad_type.cr")
    status.should_not eq(0)
    output.should contain("button requires type")
  end

  it "rejects a button type that is not a string literal" do
    status, output = crystal_build_fixture("spec/fixtures/button_dynamic_type.cr")
    status.should_not eq(0)
    output.should contain("button requires type")
  end

  it "rejects an image without alt" do
    status, output = crystal_build_fixture("spec/fixtures/img_missing_alt.cr")
    status.should_not eq(0)
    output.should contain("img requires alt")
  end

  it "rejects a document without lang" do
    status, output = crystal_build_fixture("spec/fixtures/html_missing_lang.cr")
    status.should_not eq(0)
    output.should contain("html requires lang")
  end
end
