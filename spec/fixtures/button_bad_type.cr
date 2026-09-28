require "../../src/shomen"

class ButtonBadTypeView < Shomen::View
  def to_html : String
    button type: "Submit" do
      text "Go"
    end
    result
  end
end

ButtonBadTypeView.new.to_html
