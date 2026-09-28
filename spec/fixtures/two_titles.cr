require "../../src/shomen"

class TwoTitlesView < Shomen::View
  def to_html : String
    html lang: "en" do
      head do
        title "One"
        title "Two"
      end
    end
  end
end

TwoTitlesView.new.to_html
