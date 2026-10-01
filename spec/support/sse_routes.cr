# Routes for the SSE specs. They read the store a spec sets and beat every
# 50 ms, so a stream whose client left ends quickly.
module SSERoutes
  HEARTBEAT = 50.milliseconds

  # The id the count fragment of Live carries.
  TARGET = ["count"]

  # Live sends the id of each render, so a spec knows a render ran.
  RENDERED = Channel(String).new(64)

  @@store : Shomen::Store? = nil

  def self.store=(store : Shomen::Store?) : Nil
    @@store = store
  end

  def self.store! : Shomen::Store
    @@store || raise "set SSERoutes.store first"
  end

  # The number of Noted events in the store.
  def self.count : Int32
    SpecEvents::Log.new(store!).catch_up.lines.size
  end

  def self.drain_rendered : Nil
    loop do
      select
      when RENDERED.receive
      else
        break
      end
    end
  end

  def self.next_render : String
    select
    when id = RENDERED.receive
      id
    when timeout(5.seconds)
      raise "no render within 5 seconds"
    end
  end

  class CountFragment < Shomen::Fragment
    def initialize(@id : String, @count : Int32)
    end

    def content : Nil
      id = @id
      count = @count
      p count.to_s, id: id
    end
  end

  # The count of Noted events, under the id in TARGET.
  class Live < Shomen::Route
    method GET
    path "/phase5/live"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      log = SpecEvents::Log.new(SSERoutes.store!)
      sse(SSERoutes.store!, heartbeat: SSERoutes::HEARTBEAT) do
        log.catch_up
        id = SSERoutes::TARGET[0]
        select
        when SSERoutes::RENDERED.send(id)
        else
        end
        CountFragment.new(id, log.lines.size)
      end
    end
  end

  # The id the stream's render must see.
  class MustSee < Shomen::Route
    method GET
    path "/phase7/sse-must-see"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      sse(SSERoutes.store!, heartbeat: SSERoutes::HEARTBEAT) do
        CountFragment.new("must-see", must_see.to_i32)
      end
    end
  end

  # Raises Shomen::Unavailable for the next UNAVAILABLE[0] renders after
  # an append, as a fragment that reads a lagging consumer would.
  UNAVAILABLE = [0]

  class Lagging < Shomen::Route
    method GET
    path "/phase7/sse-lagging"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      log = SpecEvents::Log.new(SSERoutes.store!)
      sse(SSERoutes.store!, heartbeat: SSERoutes::HEARTBEAT) do
        if must_see > 0 && SSERoutes::UNAVAILABLE[0] > 0
          SSERoutes::UNAVAILABLE[0] -= 1
          raise Shomen::Unavailable.new("spec did not reach event #{must_see}")
        end
        CountFragment.new("lagging", log.catch_up.lines.size)
      end
    end
  end

  # Its first render appends, as another request can between a render
  # and the wait that follows it.
  class Racing < Shomen::Route
    method GET
    path "/phase5/racing"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      store = SSERoutes.store!
      log = SpecEvents::Log.new(store)
      first = true
      sse(store, heartbeat: SSERoutes::HEARTBEAT) do
        log.catch_up
        count = log.lines.size
        if first
          first = false
          store.append("racing", 0_i64, note("during the first render"))
        end
        CountFragment.new("count", count)
      end
    end
  end

  # Its first render finds nothing.
  class Missing < Shomen::Route
    method GET
    path "/phase5/missing"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      sse(SSERoutes.store!, heartbeat: SSERoutes::HEARTBEAT) { find }
    end

    private def find : Shomen::Fragment
      raise Shomen::NotFound.new
    end
  end

  # The holder and a link that replaces it with a new one.
  class AreaFragment < Shomen::Fragment
    def initialize(@count : Int32)
    end

    def content : Nil
      count = @count
      div(id: "area") do
        div(id: "live", "data-shomen-sse": Live.path) do
          p count.to_s, id: "count"
        end
        a "Swap", href: Swap.path, "data-shomen-get": "area", id: "swap"
      end
    end
  end

  class PageView < Shomen::View
    def initialize(@area : AreaFragment)
    end

    def to_html : String
      area = @area
      html lang: "en" do
        head do
          title "Live"
          shomen_script
        end
        body do
          main do
            p "outside", id: "outside"
            embed area
            # Another origin: the page is on 127.0.0.1, and nothing listens on port 1.
            div(id: "far", "data-shomen-sse": "http://localhost:1/phase5/live") do
              p "far", id: "far-count"
            end
          end
        end
      end
    end
  end

  class Page < Shomen::Route
    method GET
    path "/phase5/live-page"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      render PageView.new(AreaFragment.new(SSERoutes.count))
    end
  end

  # Where Detour sends a stream: this server under another host name,
  # which is another origin to the page.
  FAR = [""]

  class Detour < Shomen::Route
    method GET
    path "/phase5/detour"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      redirect SSERoutes::FAR[0], 302
    end
  end

  # Lets any origin read it, so only shomen.js keeps its HTML off the page.
  class Far < Shomen::Route
    method GET
    path "/phase5/far"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      response = sse(SSERoutes.store!, heartbeat: SSERoutes::HEARTBEAT) { CountFragment.new("far-count", 99) }
      response.headers["Access-Control-Allow-Origin"] = "*"
      response
    end
  end

  class DetourView < Shomen::View
    def to_html : String
      html lang: "en" do
        head do
          title "Detour"
          shomen_script
        end
        body do
          main do
            div(id: "detour", "data-shomen-sse": Detour.path) do
              p "near", id: "far-count"
            end
          end
        end
      end
    end
  end

  class DetourPage < Shomen::Route
    method GET
    path "/phase5/detour-page"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      render DetourView.new
    end
  end

  class Swap < Shomen::Route
    method GET
    path "/phase5/swap"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      area = AreaFragment.new(SSERoutes.count)
      return render_fragment(area) if target
      render PageView.new(area)
    end
  end
end
