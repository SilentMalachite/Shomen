require "../../src/shomen"

class InputDynamicIdView < Shomen::View
  def to_html : String
    field_id = "name"
    label("Name", for: field_id)
    input(id: field_id, name: "name")
    result
  end
end

InputDynamicIdView.new.to_html
