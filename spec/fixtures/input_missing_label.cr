require "../../src/shomen"

class InputMissingLabelView < Shomen::View
  def to_html : String
    input(type: "text", name: "q")
    result
  end
end

InputMissingLabelView.new.to_html
