module BrowserRoutes
  # "METHOD path target" for each request a spec needs to count.
  RECEIVED = [] of String

  # The held destination lets its first request through (the fetch following
  # a redirect) and blocks its second (the navigation) until the spec sends
  # on HOLD_GATE. The route Arrived answers once the second request has come.
  HOLD_HITS    = [0]
  HOLD_ARRIVED = Channel(Nil).new(1)
  HOLD_GATE    = Channel(Nil).new(1)

  class SlotFragment < Shomen::Fragment
    def initialize(@message : String)
    end

    def content : Nil
      message = @message
      div(id: "slot") do
        p message
      end
    end
  end

  class FormFragment < Shomen::Fragment
    def initialize(@name : String, @token : String, @error : String?)
    end

    def content : Nil
      name = @name
      token = @token
      error = @error
      div(id: "box") do
        if message = error
          p message, role: "alert"
        end
        form(action: "/phase4/browser/form", method: "post", "data-shomen-post": "box", id: "box-form") do
          csrf_field(token)
          label("Name", for: "name")
          input(id: "name", name: "name", type: "text", value: name)
          button "Save", type: "submit", id: "save"
        end
      end
    end
  end

  class PageView < Shomen::View
    def initialize(@token : String)
    end

    def to_html : String
      token = @token
      html lang: "en" do
        head do
          title "Browser"
          shomen_script
        end
        body do
          main do
            p "outside", id: "outside"
            div(id: "slot") do
              a "Load", href: "/phase4/browser/slot", "data-shomen-get": "slot", id: "load"
            end
            a "Plain", href: "/phase4/browser/plain", "data-shomen-get": "slot", id: "plain"
            embed FormFragment.new("", token, nil)
            form(action: "/phase4/browser/hold", method: "post", "data-shomen-post": "slot", id: "hold-form") do
              csrf_field(token)
              button "Hold", type: "submit", id: "hold"
            end
            form(action: "/phase4/browser/conflict", method: "post", "data-shomen-post": "slot") do
              csrf_field(token)
              button "Clash", type: "submit", id: "clash"
            end
            a "Json", href: "/phase4/browser/json", "data-shomen-get": "slot", id: "json-link"
            form(action: "/phase4/browser/json", method: "post", "data-shomen-post": "slot", id: "json-form") do
              csrf_field(token)
              button "Json", type: "submit"
            end
            a "Short", href: "/phase4/browser/short", "data-shomen-get": "slot", id: "short-link"
            div(id: "挨拶") do
              a "Greet", href: "/phase4/browser/plain", "data-shomen-get": "挨拶", id: "greet-link"
              form(action: "/phase4/browser/greet", method: "post", "data-shomen-post": "挨拶", id: "greet-form") do
                csrf_field(token)
                button "Greet", type: "submit"
              end
            end
            div(id: "a,b") do
              form(action: "/phase4/browser/greet", method: "post", "data-shomen-post": "a,b", id: "comma-form") do
                csrf_field(token)
                button "Comma", type: "submit"
              end
            end
          end
        end
      end
    end
  end

  class PlainView < Shomen::View
    def to_html : String
      html lang: "en" do
        head do
          title "Plain"
        end
        body do
          h1 "Plain"
        end
      end
    end
  end

  class Page < Shomen::Route
    method GET
    path "/phase4/browser"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      render PageView.new(csrf_token)
    end
  end

  class Slot < Shomen::Route
    method GET
    path "/phase4/browser/slot"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      RECEIVED << "GET /phase4/browser/slot #{target || "-"}"
      if id = target
        render_fragment SlotFragment.new("loaded #{id}")
      else
        render PlainView.new
      end
    end
  end

  class Plain < Shomen::Route
    method GET
    path "/phase4/browser/plain"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      RECEIVED << "GET /phase4/browser/plain #{target || "-"}"
      render PlainView.new
    end
  end

  class Save < Shomen::Route
    method POST
    path "/phase4/browser/form"

    struct Input
      getter name : String

      def initialize(@name : String)
      end
    end

    def call(input : Input) : Shomen::Response
      RECEIVED << "POST /phase4/browser/form #{target || "-"}"
      return redirect("/phase4/browser/plain") if input.name.strip.size >= 2
      form_view = FormFragment.new(input.name, csrf_token, "Name is too short")
      return render_fragment(form_view, status: 422) if target
      render PageView.new(csrf_token), status: 422
    end
  end

  class Clash < Shomen::Route
    method POST
    path "/phase4/browser/conflict"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      RECEIVED << "POST /phase4/browser/conflict #{target || "-"}"
      raise Shomen::Conflict.new("stream browser-1 is at version 1, expected 0")
    end
  end

  class Hold < Shomen::Route
    method POST
    path "/phase4/browser/hold"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      RECEIVED << "POST /phase4/browser/hold #{target || "-"}"
      redirect("/phase4/browser/held")
    end
  end

  # A JSON value holding markup with the target's id. The onerror handler
  # would report to Pwned if the value were inserted as HTML. The attributes
  # are unquoted because JSON escapes quotes.
  JSON_MARKUP = %(<div id=slot><img src=x title=/phase4/browser/pwned onerror=fetch(this.title)></div>)

  class JsonGet < Shomen::Route
    method GET
    path "/phase4/browser/json"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      RECEIVED << "GET /phase4/browser/json #{target || "-"}"
      json({"value" => JSON_MARKUP})
    end
  end

  class JsonPost < Shomen::Route
    method POST
    path "/phase4/browser/json"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      RECEIVED << "POST /phase4/browser/json #{target || "-"}"
      json({"value" => JSON_MARKUP})
    end
  end

  class Pwned < Shomen::Route
    method GET
    path "/phase4/browser/pwned"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      RECEIVED << "GET /phase4/browser/pwned #{target || "-"}"
      render PlainView.new
    end
  end

  # With a target it declares more bytes than it sends and closes the
  # connection, so the body read fails after the headers arrived.
  class Short < Shomen::Route
    method GET
    path "/phase4/browser/short"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      RECEIVED << "GET /phase4/browser/short #{target || "-"}"
      return render PlainView.new unless target
      headers = HTTP::Headers{"Content-Length" => "100000", "Connection" => "close"}
      Shomen::Response.new(200, "text/html; charset=utf-8", %(<div id="slot"><p>short</p></div>), headers)
    end
  end

  class Greet < Shomen::Route
    method POST
    path "/phase4/browser/greet"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      RECEIVED << "POST /phase4/browser/greet #{target || "-"}"
      render PlainView.new
    end
  end

  # Answers once the held request has come, so a page can wait for it.
  class Arrived < Shomen::Route
    method GET
    path "/phase4/browser/arrived"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      HOLD_ARRIVED.receive
      render PlainView.new
    end
  end

  class Held < Shomen::Route
    method GET
    path "/phase4/browser/held"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      HOLD_HITS[0] += 1
      if HOLD_HITS[0] == 2
        HOLD_ARRIVED.send(nil)
        HOLD_GATE.receive
      end
      render PlainView.new
    end
  end
end
