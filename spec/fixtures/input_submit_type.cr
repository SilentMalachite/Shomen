require "../../src/shomen"

class InputSubmitTypeView < Shomen::View
  def to_html : String
    input(type: "submit", value: "Go")
    result
  end
end

InputSubmitTypeView.new.to_html
