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

  class HeadHome < Shomen::Route
    method HEAD
    path "/phase1/head"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      Shomen::Response.html("<h1>Hello</h1>")
    end
  end

  class Cookies < Shomen::Route
    method GET
    path "/phase1/cookies"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      headers = HTTP::Headers.new
      headers.add("Set-Cookie", "a=1")
      headers.add("Set-Cookie", "b=2")
      Shomen::Response.new(200, "text/html; charset=utf-8", "ok", headers)
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

  class Token < Shomen::Route
    method GET
    path "/phase2/token"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      Shomen::Response.html(csrf_token)
    end
  end

  class Echo < Shomen::Route
    method POST
    path "/phase2/echo"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      Shomen::Response.html("accepted")
    end
  end

  class Denied < Shomen::Route
    method GET
    path "/phase2/denied"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      raise Shomen::Forbidden.new
    end
  end

  class Signup < Shomen::Route
    method POST
    path "/phase2/signup"

    struct Input
      getter name : String
      getter age : Int32

      def initialize(@name : String, @age : Int32)
      end
    end

    def call(input : Input) : Shomen::Response
      Shomen::Response.html(Shomen::HTML.escape("#{input.name}:#{input.age}"))
    end
  end

  class Rename < Shomen::Route
    method POST
    path "/phase2/people/:id"

    struct Input
      getter id : Int64
      getter name : String

      def initialize(@id : Int64, @name : String)
      end
    end

    def call(input : Input) : Shomen::Response
      Shomen::Response.html(Shomen::HTML.escape("#{input.id}:#{input.name}"))
    end
  end

  class Invalid < Shomen::Route
    method POST
    path "/phase2/invalid"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      render HomeView.new, status: 422
    end
  end
end

module ConflictRoutes
  class Clash < Shomen::Route
    method GET
    path "/phase3/conflict"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      raise Shomen::Conflict.new("stream secret-7 is at version 2, expected 1")
    end
  end
end

module UnavailableRoutes
  class Lagging < Shomen::Route
    method GET
    path "/phase7/unavailable"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      raise Shomen::Unavailable.new("secret-8 did not reach event 7 within 00:00:02")
    end
  end
end
