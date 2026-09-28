require "../../src/shomen"

class ButtonDynamicTypeView < Shomen::View
  def initialize(@type : String)
  end

  def to_html : String
    button type: @type do
      text "Go"
    end
    result
  end
end

ButtonDynamicTypeView.new("submit").to_html
