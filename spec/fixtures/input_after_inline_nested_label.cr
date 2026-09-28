require "../../src/shomen"

class InputAfterInlineNestedLabelView < Shomen::View
  def to_html : String
    label { span { text "Query" }; input(name: "q") }
    input(name: "r")
    result
  end
end

InputAfterInlineNestedLabelView.new.to_html
