require "../../src/shomen"

class FragmentWithHtml < Shomen::Fragment
  def content : Nil
    html lang: "en" do
      head do
        title "Nested"
      end
    end
  end
end

FragmentWithHtml.new.to_html
