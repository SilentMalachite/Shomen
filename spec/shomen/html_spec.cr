require "../spec_helper"

describe Shomen::HTML do
  it "escapes text for HTML" do
    Shomen::HTML.escape("&<>\"'").should eq("&amp;&lt;&gt;&quot;&#39;")
  end

  it "escapes ampersand first" do
    Shomen::HTML.escape("&amp;").should eq("&amp;amp;")
  end

  it "leaves plain text unchanged" do
    Shomen::HTML.escape("plain").should eq("plain")
  end
end
