require "../../src/shomen"

class InputLabelMismatchView < Shomen::View
  def to_html : String
    label("Name", for: "other")
    input(id: "name", name: "name")
    result
  end
end

InputLabelMismatchView.new.to_html
