require "../../src/shomen"

class HtmlMissingLangView < Shomen::View
  def to_html : String
    html do
      title "Hello"
    end
  end
end

HtmlMissingLangView.new.to_html
