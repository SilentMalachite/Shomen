require "../../src/shomen"

class ImgMissingAltView < Shomen::View
  def to_html : String
    img src: "/x.png"
    result
  end
end

ImgMissingAltView.new.to_html
