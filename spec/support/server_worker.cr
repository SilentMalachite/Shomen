# The server the process specs start
# (docs/decisions/20260929-phase6-process-spec.md). Arguments: the port (0
# for an ephemeral one), "reuse" or "single", and the shutdown limit in
# seconds. WORKER_DATABASE_URL names the store, WORKER_REPLICA_URL its
# replica if any, and WORKER_POLL_MS its poll interval in milliseconds
# (5000 unless set).
require "../../src/shomen"
require "./events"
require "./projections"

module Worker
  STORE = Shomen::Store.new(
    ENV["WORKER_DATABASE_URL"],
    poll_interval: (ENV["WORKER_POLL_MS"]? || "5000").to_i.milliseconds,
    replica: ENV["WORKER_REPLICA_URL"]?,
  )
  NOTES = SpecEvents::Log.new(STORE)

  class Ping < Shomen::Route
    method GET
    path "/worker/ping"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      Shomen::Response.html("pong")
    end
  end

  # Writes "slow" and answers once the spec writes a line to standard input.
  class Slow < Shomen::Route
    method GET
    path "/worker/slow"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      STDOUT.puts "slow"
      STDOUT.flush
      STDIN.gets
      Shomen::Response.html("slow done")
    end
  end

  # Sends SIGINT to this process twice, as a fast double Ctrl-C would. Both
  # wait in the signal pipe before either handler runs.
  class Signals < Shomen::Route
    method GET
    path "/worker/signals"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      Process.signal(Signal::INT, Process.pid)
      Process.signal(Signal::INT, Process.pid)
      Shomen::Response.html("sent")
    end
  end

  # Writes "stall" and waits for a line on standard input. Then it writes
  # "stalling" and burns CPU for 5 seconds without yielding, so the event
  # loop cannot run a signal handler in that time.
  class Stall < Shomen::Route
    method GET
    path "/worker/stall"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      STDOUT.puts "stall"
      STDOUT.flush
      STDIN.gets
      STDOUT.puts "stalling"
      STDOUT.flush
      deadline = Time.instant + 5.seconds
      until Time.instant >= deadline
      end
      Shomen::Response.html("stalled")
    end
  end

  class CountFragment < Shomen::Fragment
    def initialize(@count : Int32)
    end

    def content : Nil
      count = @count
      p count.to_s, id: "count"
    end
  end

  class Stream < Shomen::Route
    method GET
    path "/worker/stream"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      sse(STORE) { CountFragment.new(NOTES.catch_up.lines.size) }
    end
  end

  class NotesView < Shomen::View
    def initialize(@texts : Array(String), @version : Int64, @token : String)
    end

    def to_html : String
      texts = @texts
      version = @version
      token = @token
      html lang: "en" do
        head do
          title "Notes"
        end
        body do
          main do
            ul do
              texts.each { |text| li text }
            end
            form(action: Add.path, method: "post") do
              csrf_field(token)
              input(type: "hidden", name: "version", value: version.to_s)
              label("Text", for: "text")
              input(id: "text", name: "text", type: "text")
              button "Add", type: "submit"
            end
          end
        end
      end
    end
  end

  class Notes < Shomen::Route
    method GET
    path "/worker/notes"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      lines = NOTES.catch_up(must_see, within: 300.milliseconds).lines
      render NotesView.new(lines.map(&.text), lines.size.to_i64, csrf_token)
    end
  end

  class Add < Shomen::Route
    method POST
    path "/worker/notes"

    struct Input
      getter text : String
      getter version : Int64

      def initialize(@text : String, @version : Int64)
      end
    end

    def call(input : Input) : Shomen::Response
      remember STORE.append("notes", input.version, [SpecEvents::Noted.new(input.text)] of Shomen::Event)
      redirect Notes.path
    end
  end
end

port, mode, limit = ARGV
Shomen::Server.start(port: port.to_i, reuse_port: mode == "reuse", shutdown_timeout: limit.to_f.seconds)
Worker::STORE.close
