# Routes for the ETag and fragment cache specs. CALLS records, in order,
# when a validator, a route's call, and a view ran.
module ETagRoutes
  CALLS = [] of String

  @@store : Shomen::Store? = nil

  def self.store=(store : Shomen::Store?) : Nil
    @@store = store
  end

  def self.store! : Shomen::Store
    @@store || raise "set ETagRoutes.store first"
  end

  class PageView < Shomen::View
    def initialize(@version : String)
    end

    def to_html : String
      ETagRoutes::CALLS << "view"
      version = @version
      html lang: "en" do
        head do
          title "Page"
        end
        body do
          h1 version
        end
      end
    end
  end

  class Page < Shomen::Route
    method GET
    path "/phase7/etag/:version"

    struct Input
      getter version : String

      def initialize(@version : String)
      end
    end

    def validator(input : Input) : String
      ETagRoutes::CALLS << "validator"
      input.version
    end

    def call(input : Input) : Shomen::Response
      ETagRoutes::CALLS << "call"
      render PageView.new(input.version)
    end
  end

  class OwnCacheControl < Shomen::Route
    method GET
    path "/phase7/etag-own-cache"

    struct Input
    end

    def validator(input : Input) : String
      "own"
    end

    def cache_control : String
      "private, max-age=60"
    end

    def call(input : Input) : Shomen::Response
      render PageView.new("own")
    end
  end

  # Sets a Cache-Control in call that its 304 would not send.
  class CallCacheControl < Shomen::Route
    method GET
    path "/phase7/etag-call-cache"

    struct Input
    end

    def validator(input : Input) : String
      "call"
    end

    def call(input : Input) : Shomen::Response
      response = render PageView.new("call")
      response.headers["Cache-Control"] = "private, max-age=60"
      response
    end
  end

  class RememberingValidator < Shomen::Route
    method GET
    path "/phase7/etag-remember"

    struct Input
    end

    def validator(input : Input) : String
      remember 7_i64
      "remember"
    end

    def call(input : Input) : Shomen::Response
      render PageView.new("remember")
    end
  end

  class Moved < Shomen::Route
    method GET
    path "/phase7/etag-moved"

    struct Input
    end

    def validator(input : Input) : String
      "moved"
    end

    def call(input : Input) : Shomen::Response
      redirect "/phase1/home"
    end
  end

  class Stream < Shomen::Route
    method GET
    path "/phase7/etag-stream"

    struct Input
    end

    def validator(input : Input) : String
      "stream"
    end

    def call(input : Input) : Shomen::Response
      sse(ETagRoutes.store!) { FragmentRoutes::NoteFragment.new("stream") }
    end
  end

  CACHE = Shomen::FragmentCache.new

  # A fragment of the HTML it is given, so a spec knows its size.
  class TextFragment < Shomen::Fragment
    def initialize(@text : String)
    end

    def content : Nil
      raw @text
    end
  end

  class EmbedView < Shomen::View
    def initialize(@fragment : Shomen::Fragment)
    end

    def to_html : String
      fragment = @fragment
      html lang: "en" do
        head do
          title "Cached"
        end
        body do
          embed fragment
        end
      end
    end
  end

  class CachedPage < Shomen::Route
    method GET
    path "/phase7/cached/:version"

    struct Input
      getter version : String

      def initialize(@version : String)
      end
    end

    def call(input : Input) : Shomen::Response
      fragment = cached(ETagRoutes::CACHE, "note", input.version) do
        ETagRoutes::CALLS << "render"
        FragmentRoutes::NoteFragment.new(input.version)
      end
      return render_fragment(fragment) if target
      render EmbedView.new(fragment)
    end
  end

  class CachedToken < Shomen::Route
    method GET
    path "/phase7/cached-token"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      token = csrf_token
      render_fragment(cached(ETagRoutes::CACHE, "token") { TextFragment.new(%(<input type="hidden" value="#{token}">)) })
    end
  end
end
