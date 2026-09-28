require "../../src/shomen"

class InputInHelperMethodView < Shomen::View
  def to_html : String
    label("Name", for: "name")
    field
    result
  end

  private def field : Nil
    input(id: "name", name: "name")
  end
end

InputInHelperMethodView.new.to_html
