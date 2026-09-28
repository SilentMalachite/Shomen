require "../../src/shomen"

class InputHelperWithoutLabelView < Shomen::View
  def to_html : String
    field
    result
  end

  private def field : Nil
    input(id: "name", name: "name")
  end
end

InputHelperWithoutLabelView.new.to_html
