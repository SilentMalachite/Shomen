require "../spec_helper"

describe Shomen::Fragment do
  it "renders its element without a document" do
    FragmentRoutes::NoteFragment.new("<hi>").to_html.should eq("<div id=\"note\"><p>&lt;hi&gt;</p></div>")
  end

  it "renders the same html each time" do
    note = FragmentRoutes::NoteFragment.new("a")
    note.to_html.should eq(note.to_html)
  end

  it "is embedded in a document view" do
    FragmentRoutes::NotePage.new("<hi>").to_html.should eq(
      "<!DOCTYPE html><html lang=\"en\"><head><title>Note</title></head>" \
      "<body><main><h1>Note</h1><div id=\"note\"><p>&lt;hi&gt;</p></div></main></body></html>"
    )
  end

  it "is sent alone by render_fragment" do
    headers = HTTP::Headers{"Shomen-Target" => "note"}
    response = call_with(Shomen::Server.new, "GET", "/phase4/note", headers: headers)
    response.status_code.should eq(200)
    response.headers["Content-Type"].should eq("text/html; charset=utf-8")
    response.body.should eq("<div id=\"note\"><p>&lt;saved&gt;</p></div>")
  end

  it "keeps the status given to render_fragment" do
    response = FragmentRoutes::Note.new.render_fragment(FragmentRoutes::NoteFragment.new("x"), status: 422)
    response.status.should eq(422)
    response.body.should eq("<div id=\"note\"><p>x</p></div>")
  end

  it "rejects html inside a fragment at compile time" do
    status, output = crystal_build_fixture("spec/fixtures/fragment_with_html.cr")
    status.should_not eq(0)
    output.should contain("a fragment cannot contain html")
  end

  it "rejects render with a fragment at compile time" do
    status, output = crystal_build_fixture("spec/fixtures/render_with_fragment.cr")
    status.should_not eq(0)
    output.should contain("render takes a document view")
  end

  it "rejects render_fragment with a document view at compile time" do
    status, output = crystal_build_fixture("spec/fixtures/render_fragment_with_document.cr")
    status.should_not eq(0)
    output.should contain("to be Shomen::Fragment, not DocumentPage")
  end
end
