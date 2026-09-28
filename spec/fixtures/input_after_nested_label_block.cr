require "../../src/shomen"

class InputAfterNestedLabelBlockView < Shomen::View
  def to_html : String
    div do
      div do
        p "Intro"
      end
      label do
        span do
          text "Query"
        end
      end
      input(name: "q")
    end
    result
  end
end

InputAfterNestedLabelBlockView.new.to_html
