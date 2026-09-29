module FragmentRoutes
  class NoteFragment < Shomen::Fragment
    def initialize(@message : String)
    end

    def content : Nil
      message = @message
      div(id: "note") do
        p message
      end
    end
  end

  class NotePage < Shomen::View
    def initialize(@message : String)
    end

    def to_html : String
      message = @message
      html lang: "en" do
        head do
          title "Note"
        end
        body do
          main do
            h1 "Note"
            embed NoteFragment.new(message)
          end
        end
      end
    end
  end

  class Note < Shomen::Route
    method GET
    path "/phase4/note"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      return render_fragment NoteFragment.new("<saved>") if target
      render NotePage.new("<saved>")
    end
  end

  class Target < Shomen::Route
    method GET
    path "/phase4/target"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      Shomen::Response.html(Shomen::HTML.escape(target || "none"))
    end
  end

  class PostTarget < Shomen::Route
    method POST
    path "/phase4/target"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      Shomen::Response.html(Shomen::HTML.escape(target || "none"))
    end
  end

  class Json < Shomen::Route
    method GET
    path "/phase4/json"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      json({name: "<Ada>", count: 2}, status: 201)
    end
  end

  class JsonMissing < Shomen::Route
    method GET
    path "/phase4/json/missing"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      raise Shomen::NotFound.new
    end
  end
end
