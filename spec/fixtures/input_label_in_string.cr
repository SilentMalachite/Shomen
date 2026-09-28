require "../../src/shomen"

class InputLabelInStringView < Shomen::View
  def to_html : String
    p "label(for: \"a\")"
    input(id: "a", name: "a")
    result
  end
end

InputLabelInStringView.new.to_html
