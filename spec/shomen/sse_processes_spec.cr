require "../spec_helper"
require "socket"

# Opens /worker/stream on a server process over url, appends one event
# through another process, and reads the count the stream sends again.
# Each read waits at most 3 seconds, shorter than the default poll.
private def stream_across_processes(url : String, poll_ms : String, &) : Nil
  Workers.binary("spec/support/store_worker.cr")
  with_server_process(env: {"WORKER_DATABASE_URL" => url, "WORKER_POLL_MS" => poll_ms}) do |server|
    TCPSocket.open("127.0.0.1", server.port) do |socket|
      socket.read_timeout = 3.seconds
      send_get(socket, "/worker/stream")
      read_until(socket, %(data: <p id="count">0</p>))
      yield
      append_elsewhere(url, "from-another-process", 1)
      read_until(socket, %(data: <p id="count">1</p>))
    end
  end
end

describe "an SSE stream" do
  it "receives an event appended through another process on one SQLite file, by polling" do
    path = File.tempname("shomen-sse", ".sqlite3")
    begin
      stream_across_processes("sqlite3://#{path}", "50") { }
    ensure
      remove_database(path)
    end
  end

  postgres_database_it "receives an event appended through another process on one Postgres database, by notification" do |url|
    # The poll is an hour away, so only the notification can wake the stream.
    stream_across_processes(url, "3600000") do
      DB.open(url) { |db| wait_until(20.seconds) { PostgresSpec.listeners(db).size == 1 } }
    end
  end
end
