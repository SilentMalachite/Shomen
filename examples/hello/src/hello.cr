require "shomen"
require "./users"
require "./counter"

module Hello
  class ShowView < Shomen::View
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

  class Show < Shomen::Route
    method GET
    path "/"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      render ShowView.new
    end
  end
end

module Greeting
  class FormView < Shomen::Fragment
    def initialize(@name : String, @token : String, @error : String?)
    end

    def content : Nil
      name = @name
      token = @token
      error = @error
      div(id: "greeting-form") do
        if message = error
          p message, role: "alert"
        end
        form(action: Greeting::Update.path, method: "post", "data-shomen-post": "greeting-form") do
          csrf_field(token)
          label("Name", for: "name")
          input(id: "name", name: "name", type: "text", value: name)
          button "Save", type: "submit", id: "greeting-save"
        end
      end
    end
  end

  class EditView < Shomen::View
    def initialize(@form : FormView)
    end

    def to_html : String
      form_view = @form
      html lang: "en" do
        head do
          title "Greeting"
          shomen_script
        end
        body do
          main do
            h1 "Greeting"
            embed form_view
          end
        end
      end
    end
  end

  class ShowView < Shomen::View
    def initialize(@name : String)
    end

    def to_html : String
      name = @name
      html lang: "en" do
        head do
          title "Greeting"
          shomen_script
        end
        body do
          main do
            h1 "Hello, #{name}"
            div(id: "greeting-form") do
              a "Change", href: Greeting::Edit.path, "data-shomen-get": "greeting-form"
            end
          end
        end
      end
    end
  end

  class Edit < Shomen::Route
    method GET
    path "/greeting"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      form_view = FormView.new("", csrf_token, nil)
      return render_fragment(form_view) if target
      render EditView.new(form_view)
    end
  end

  class Update < Shomen::Route
    method POST
    path "/greeting"

    struct Input
      getter name : String

      def initialize(@name : String)
      end
    end

    def call(input : Input) : Shomen::Response
      name = input.name.strip
      return redisplay(input.name, "Name must be at least 2 characters") if name.size < 2
      # The path helper refuses these characters in a path parameter.
      if name.includes?('/') || name.includes?('?') || name.includes?('#')
        return redisplay(input.name, "Name must not contain /, ?, or #")
      end
      # The path helper refuses .. too, since a browser resolves /greeting/.. to /.
      return redisplay(input.name, "Name must not be ..") if name == ".."
      redirect Show.path(name: name)
    end

    private def redisplay(name : String, error : String) : Shomen::Response
      form_view = FormView.new(name, csrf_token, error)
      return render_fragment(form_view, status: 422) if target
      render EditView.new(form_view), status: 422
    end
  end

  class Show < Shomen::Route
    method GET
    path "/greeting/:name"

    struct Input
      getter name : String

      def initialize(@name : String)
      end
    end

    def call(input : Input) : Shomen::Response
      render ShowView.new(input.name)
    end
  end
end

unless ENV["SHOMEN_SPEC"]?
  Users::NAMES.catch_up
  Shomen::Server.start
end
