require "../../src/shomen"

class TitleOnlyInRegexView < Shomen::View
  def to_html : String
    html lang: "en" do
      body do
        p /title()/.source
      end
    end
  end
end

TitleOnlyInRegexView.new.to_html
