module CSPRoutes
  # A document with an inline script, which the default policy stops.
  class InlineView < Shomen::View
    def to_html : String
      html lang: "en" do
        head do
          title "Inline"
        end
        body do
          h1 "Inline"
          raw "<script>window.inlineRan = true;</script>"
        end
      end
    end
  end

  class Inline < Shomen::Route
    method GET
    path "/phase6/csp/inline"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      render InlineView.new
    end
  end

  # The same document under a policy the route sets itself.
  class Own < Shomen::Route
    method GET
    path "/phase6/csp/own"

    POLICY = "script-src 'self' 'unsafe-inline'"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      headers = HTTP::Headers{"Content-Security-Policy" => POLICY}
      Shomen::Response.new(200, "text/html; charset=utf-8", InlineView.new.to_html, headers)
    end
  end
end
