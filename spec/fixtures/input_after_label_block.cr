require "../../src/shomen"

class InputAfterLabelBlockView < Shomen::View
  def to_html : String
    label do
      text "Query"
    end
    input(name: "q")
    result
  end
end

InputAfterLabelBlockView.new.to_html
