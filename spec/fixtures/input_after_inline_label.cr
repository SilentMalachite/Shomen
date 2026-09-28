require "../../src/shomen"

class InputAfterInlineLabelView < Shomen::View
  def to_html : String
    label { text "Query" }
    input(name: "q")
    result
  end
end

InputAfterInlineLabelView.new.to_html
