require "../../src/shomen"

class InputSelfCallView < Shomen::View
  def to_html : String
    self.input(name: "q")
    result
  end
end

InputSelfCallView.new.to_html
