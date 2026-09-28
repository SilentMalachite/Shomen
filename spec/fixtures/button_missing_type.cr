require "../../src/shomen"

class ButtonMissingTypeView < Shomen::View
  def to_html : String
    button do
      text "Go"
    end
    result
  end
end

ButtonMissingTypeView.new.to_html
