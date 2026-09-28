class Shomen::ErrorView < Shomen::View
  def initialize(@heading : String, @detail : String?)
  end

  def to_html : String
    heading = @heading
    detail = @detail
    html lang: "en" do
      head do
        title heading
      end
      body do
        h1 heading
        if text = detail
          p text
        end
      end
    end
  end
end
