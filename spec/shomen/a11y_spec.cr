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

private class LabeledForm < Shomen::View
  def to_html : String
    form(action: "/save", method: "post") do
      csrf_field("tok")
      label("Name", for: "name")
      input(id: "name", name: "name", type: "text")
      label do
        text "Email"
        input(name: "email", type: "email")
      end
      input(name: "q", type: "search", "aria-label": "Search")
      input(type: "hidden", name: "step", value: "1")
    end
    result
  end
end

private class LabeledBase < Shomen::View
  def to_html : String
    result
  end
end

private class LabeledChild < LabeledBase
  def to_html : String
    label do
      input(name: "q")
    end
    result
  end
end

private class InlineLabels < Shomen::View
  def to_html : String
    label { input(name: "q") }
    label { span { text "Tag" }; input(name: "tag") }
    result
  end
end

private class LabelInOtherMethod < Shomen::View
  def to_html : String
    label("Name", for: "name")
    field
    result
  end

  private def field : Nil
    input(id: "name", name: "name")
  end
end

private class LabelingParent < Shomen::View
  def to_html : String
    label("Name", for: "name")
    result
  end
end

private class LabeledByParent < LabelingParent
  def to_html : String
    input(id: "name", name: "name")
    result
  end
end

private class LabelledBy < Shomen::View
  def to_html : String
    h2 "Search", id: "search-heading"
    self.input(name: "q", "aria-labelledby": "search-heading")
    result
  end
end

describe Shomen::View do
  it "accepts a label in another method of the same view" do
    LabelInOtherMethod.new.to_html.should eq("<label for=\"name\">Name</label><input id=\"name\" name=\"name\">")
  end

  it "accepts a label in a parent view" do
    LabeledByParent.new.to_html.should eq("<input id=\"name\" name=\"name\">")
  end

  it "accepts aria-labelledby" do
    LabelledBy.new.to_html.should contain("<input name=\"q\" aria-labelledby=\"search-heading\">")
  end

  it "accepts inputs with a for label, a wrapping label, aria-label, or hidden type" do
    html = LabeledForm.new.to_html
    html.should contain("<input type=\"hidden\" name=\"_csrf\" value=\"tok\">")
    html.should contain("<label for=\"name\">Name</label><input id=\"name\" name=\"name\" type=\"text\">")
    html.should contain("<label>Email<input name=\"email\" type=\"email\"></label>")
    html.should contain("<input name=\"q\" type=\"search\" aria-label=\"Search\">")
    html.should contain("<input type=\"hidden\" name=\"step\" value=\"1\">")
  end

  it "accepts inputs inside one-line label blocks" do
    InlineLabels.new.to_html.should eq("<label><input name=\"q\"></label><label><span>Tag</span><input name=\"tag\"></label>")
  end

  it "checks a view that inherits from another view" do
    LabeledChild.new.to_html.should eq("<label><input name=\"q\"></label>")
  end

  {
    "input_missing_label"             => "an input without a label",
    "input_label_mismatch"            => "a label whose for does not match the input id",
    "input_after_label_block"         => "an input after a label block closes",
    "input_after_inline_label"        => "an input after a one-line label block",
    "input_after_inline_nested_label" => "an input after a one-line label block that holds a nested block",
    "input_label_in_string"           => "a label call that only appears inside a string",
    "input_helper_without_label"      => "an input in a helper method of a view without a matching label",
    "input_in_included_module"        => "an input in a module included into a view",
    "input_self_call"                 => "an input called through self",
    "input_empty_aria_label"          => "an input with an empty aria-label",
    "input_dynamic_id"                => "an input whose id is not a string literal",
    "input_submit_type"               => "a submit input",
  }.each do |fixture, description|
    it "rejects #{description}" do
      status, output = crystal_build_fixture("spec/fixtures/#{fixture}.cr")
      status.should_not eq(0)
      output.should contain("input needs a label")
    end
  end

  it "says that for: and id: must be string literals" do
    _, output = crystal_build_fixture("spec/fixtures/input_dynamic_id.cr")
    output.should contain("string literal")
  end

  it "points a submit input to button" do
    _, output = crystal_build_fixture("spec/fixtures/input_submit_type.cr")
    output.should contain("use button")
  end

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
