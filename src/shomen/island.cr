require "./route"

# Serves the official JavaScript. The file is read at compile time, so
# the binary carries it wherever it runs and nothing builds it.
module Shomen::Island
  SOURCE = {{ read_file("#{__DIR__}/assets/shomen.js") }}

  class Script < Shomen::Route
    method GET
    path "/shomen.js"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      headers = HTTP::Headers.new
      headers["X-Content-Type-Options"] = "nosniff"
      Shomen::Response.new(200, "text/javascript; charset=utf-8", SOURCE, headers)
    end
  end
end
