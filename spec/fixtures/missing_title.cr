require "../../src/shomen"

class MissingTitleView < Shomen::View
  def to_html : String
    html lang: "en" do
      body do
        h1 "Hello"
        p "title in text only"
      end
    end
  end
end

MissingTitleView.new.to_html
