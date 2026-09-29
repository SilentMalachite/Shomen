require "../../src/shomen/store"
require "../../src/shomen/command"
require "./events"

# Appends count events to stream. With a fourth argument "wait", it opens
# the store, writes "ready", and appends after a line on standard input
# (docs/decisions/20260929-phase6-process-spec.md).
url, stream, count = ARGV
store = Shomen::Store.new(url)
if ARGV[3]? == "wait"
  STDOUT.puts "ready"
  STDOUT.flush
  STDIN.gets
end
count.to_i64.times do |version|
  store.append(stream, version, [SpecEvents::Noted.new("#{stream} #{version}")] of Shomen::Event)
end
store.close
