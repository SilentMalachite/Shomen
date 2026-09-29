require "../../src/shomen"

class DocumentPage < Shomen::View
  def to_html : String
    html lang: "en" do
      head do
        title "Page"
      end
    end
  end
end

class RenderFragmentWithDocument < Shomen::Route
  method GET
  path "/fixture"

  struct Input
  end

  def call(input : Input) : Shomen::Response
    render_fragment DocumentPage.new
  end
end

Shomen::Router.entries
