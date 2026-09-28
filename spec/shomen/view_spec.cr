require "../spec_helper"

private class TagProbe < Shomen::View
  def initialize(@tag : String, @content : String)
  end

  def to_html : String
    case @tag
    when "head"     then head(@content)
    when "body"     then body(@content)
    when "header"   then header(@content)
    when "main"     then main(@content)
    when "footer"   then footer(@content)
    when "nav"      then nav(@content)
    when "h1"       then h1(@content)
    when "h2"       then h2(@content)
    when "h3"       then h3(@content)
    when "p"        then p(@content)
    when "div"      then div(@content)
    when "span"     then span(@content)
    when "ul"       then ul(@content)
    when "ol"       then ol(@content)
    when "li"       then li(@content)
    when "a"        then a(@content)
    when "form"     then form(@content)
    when "label"    then label(@content)
    when "textarea" then textarea(@content)
    when "title"    then title(@content)
    else                 raise "unknown tag #{@tag}"
    end
    result
  end
end

private class EscapeProbe < Shomen::View
  def to_html : String
    h1("<Hi & Co>")
    result
  end
end

private class RawProbe < Shomen::View
  def to_html : String
    div do
      raw("<b>ok</b>")
    end
    result
  end
end

private class AttributeProbe < Shomen::View
  def to_html : String
    a("Hello", href: "/a?b=1&c=2")
    result
  end
end

private class LabelForProbe < Shomen::View
  def to_html : String
    label("Name", for: "name", class: "field")
    result
  end
end

private class VoidProbe < Shomen::View
  def to_html : String
    meta(charset: "utf-8")
    input(type: "text", name: "q")
    result
  end
end

describe Shomen::View do
  %w(head body header main footer nav h1 h2 h3 p div span ul ol li a form label textarea title).each do |tag|
    it "renders #{tag}" do
      html = TagProbe.new(tag, "Hi").to_html
      html.should contain("<#{tag}>Hi</#{tag}>")
    end
  end

  it "escapes element text" do
    EscapeProbe.new.to_html.should contain("<h1>&lt;Hi &amp; Co&gt;</h1>")
  end

  it "inserts raw markup only through raw" do
    RawProbe.new.to_html.should contain("<div><b>ok</b></div>")
  end

  it "escapes attribute values" do
    AttributeProbe.new.to_html.should contain("<a href=\"/a?b=1&amp;c=2\">Hello</a>")
  end

  it "accepts for and class attributes" do
    LabelForProbe.new.to_html.should contain("<label for=\"name\" class=\"field\">Name</label>")
  end

  it "renders void elements without a closing tag" do
    html = VoidProbe.new.to_html
    html.should contain("<meta charset=\"utf-8\">")
    html.should contain("<input type=\"text\" name=\"q\">")
    html.should_not contain("</input>")
    html.should_not contain("</meta>")
  end
end
