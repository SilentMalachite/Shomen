require "spec"
ENV["SHOMEN_SECRET"] = "spec-secret"
require "../src/shomen"
require "log/spec"
require "./support/process"
require "./support/client"
require "./support/env"
require "./support/workers"
require "./support/postgres"
require "./support/wait"
require "./support/routes"
require "./support/events"
require "./support/store"
require "./support/projections"
require "./support/fragment_routes"
require "./support/browser"
require "./support/browser_routes"
require "./support/sse_client"
require "./support/sse_routes"
require "./support/island_routes"
require "./support/page_spy"
require "./support/islands_page"
require "./support/csp_routes"
require "./support/server_process"

# Specs read the log with Log.capture; nothing else prints it.
Log.setup(:none)

Spec.after_suite { Workers.remove }
