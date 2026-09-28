require "../../src/shomen"

module SearchField
  def search_field : Nil
    input(name: "q")
  end
end

class InputInIncludedModuleView < Shomen::View
  include SearchField

  def to_html : String
    search_field
    result
  end
end

InputInIncludedModuleView.new.to_html
