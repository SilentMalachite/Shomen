module IslandRoutes
  Shomen::Island.script "counter", "islands/counter.js"
  # A name with a digit after '-' and the same name without the '-'.
  Shomen::Island.script "counter-2", "islands/counter.js"
  Shomen::Island.script "counter2", "islands/counter.js"

  # An island of the counter module: a count and the button it shows.
  class CounterFragment < Shomen::Fragment
    def initialize(@id : String, @name : String, @start : Int32)
    end

    def content : Nil
      id = @id
      name = @name
      start = @start
      div("data-shomen-island": name, id: id) do
        p start.to_s, id: "#{id}-value"
        button "Add", type: "button", id: "#{id}-add", hidden: "hidden"
      end
    end
  end

  class MoreFragment < Shomen::Fragment
    def content : Nil
      div(id: "more") do
        embed CounterFragment.new("second", "counter", 10)
      end
    end
  end

  class PageView < Shomen::View
    def initialize(@count : Int32)
    end

    def to_html : String
      count = @count
      html lang: "en" do
        head do
          title "Islands"
          shomen_script
        end
        body do
          main do
            # Used as a path, this name would lead to /islands/counter.js.
            embed CounterFragment.new("bad", "counter/../counter", 0)
            embed CounterFragment.new("first", "counter", 0)
            div(id: "more") do
              a "More", href: More.path, "data-shomen-get": "more", id: "more-link"
            end
            div(id: "live", "data-shomen-sse": SSERoutes::Live.path) do
              p count.to_s, id: "count"
            end
          end
        end
      end
    end
  end

  class Page < Shomen::Route
    method GET
    path "/phase5/islands"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      render PageView.new(SSERoutes.count)
    end
  end

  class More < Shomen::Route
    method GET
    path "/phase5/islands/more"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      return render_fragment(MoreFragment.new) if target
      render PageView.new(SSERoutes.count)
    end
  end
end
