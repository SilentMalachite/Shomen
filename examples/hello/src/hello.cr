require "shomen"

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
  class EditView < Shomen::View
    def initialize(@name : String, @token : String, @error : String?)
    end

    def to_html : String
      name = @name
      token = @token
      error = @error
      html lang: "en" do
        head do
          title "Greeting"
        end
        body do
          main do
            h1 "Greeting"
            if message = error
              p message
            end
            form(action: Greeting::Update.path, method: "post") do
              csrf_field(token)
              label("Name", for: "name")
              input(id: "name", name: "name", type: "text", value: name)
              button "Save", type: "submit"
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
      render EditView.new("", csrf_token, nil)
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
      if input.name.strip.size < 2
        return render EditView.new(input.name, csrf_token, "Name must be at least 2 characters"), status: 422
      end
      redirect Edit.path
    end
  end
end

Shomen::Server.start unless ENV["SHOMEN_SPEC"]?
