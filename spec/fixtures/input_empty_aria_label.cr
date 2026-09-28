require "../../src/shomen"

class InputEmptyAriaLabelView < Shomen::View
  def to_html : String
    input(name: "q", "aria-label": "")
    result
  end
end

InputEmptyAriaLabelView.new.to_html
