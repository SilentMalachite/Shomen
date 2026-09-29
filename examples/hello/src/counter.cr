module Counter
  Shomen::Island.script "counter", "counter.js"

  class ShowView < Shomen::View
    def to_html : String
      html lang: "en" do
        head do
          title "Counter"
          shomen_script
        end
        body do
          main do
            h1 "Counter"
            # Without JavaScript the button would do nothing, so it stays
            # hidden until the island runs.
            div("data-shomen-island": "counter", id: "counter") do
              p "0", id: "counter-value", "aria-live": "polite"
              button "Add one", type: "button", id: "counter-add", hidden: "hidden"
            end
          end
        end
      end
    end
  end

  class Show < Shomen::Route
    method GET
    path "/counter"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      render ShowView.new
    end
  end
end
