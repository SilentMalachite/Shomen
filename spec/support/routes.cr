require "http"

module ServerRoutes
  class HomeView < Shomen::View
    def to_html : String
      html lang: "en" do
        head do
          title "Hello"
        end
        body do
          h1 "Hello"
        end
      end
    end
  end

  class Home < Shomen::Route
    method GET
    path "/phase1/home"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      render HomeView.new
    end
  end

  class User < Shomen::Route
    method GET
    path "/phase1/people/:id"

    struct Input
      getter id : Int32

      def initialize(@id : Int32)
      end
    end

    def call(input : Input) : Shomen::Response
      render_text = input.id.to_s
      Shomen::Response.html(render_text)
    end
  end

  class NewPerson < Shomen::Route
    method GET
    path "/phase1/people/new"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      Shomen::Response.html("new")
    end
  end

  class Boom < Shomen::Route
    method GET
    path "/phase1/boom"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      raise "boom <script>"
    end
  end

  class Gone < Shomen::Route
    method GET
    path "/phase1/gone"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      raise Shomen::NotFound.new
    end
  end

  class Bad < Shomen::Route
    method GET
    path "/phase1/bad/:id"

    struct Input
      getter id : Int32

      def initialize(@id : Int32)
      end
    end

    def call(input : Input) : Shomen::Response
      Shomen::Response.html(input.id.to_s)
    end
  end

  class Redirector < Shomen::Route
    method GET
    path "/phase1/redirect"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      redirect("/phase1/home")
    end
  end

  class Update < Shomen::Route
    method POST
    path "/phase1/home"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      Shomen::Response.html("posted")
    end
  end
end
