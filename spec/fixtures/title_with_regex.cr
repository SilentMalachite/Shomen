require "../../src/shomen"

class TitleWithRegexView < Shomen::View
  def to_html : String
    html lang: "en" do
      head do
        title "Hello"
      end
      body do
        p /title()/.source
        p %r{title()}.source
      end
    end
  end
end

TitleWithRegexView.new.to_html
