# Runs SpecConsumers::Notes on the store at the URL until a line on
# standard input, then stops it and closes the store
# (docs/decisions/20260929-phase6-process-spec.md). Arguments: the store
# URL, and "run" or "stall". With "stall", the consumer writes "stalled"
# after the row of the event "stall" and never ends that batch.
require "../../src/shomen"
require "./events"
require "./consumers"

class StallingNotes < SpecConsumers::Notes
  def write(recorded : Shomen::Recorded, connection : DB::Connection) : Nil
    super
    event = recorded.event
    if event.is_a?(SpecEvents::Noted) && event.text == "stall"
      STDOUT.puts "stalled"
      STDOUT.flush
      Channel(Nil).new.receive
    end
  end
end

url, mode = ARGV
store = Shomen::Store.new(url, poll_interval: 50.milliseconds)
consumer = mode == "stall" ? StallingNotes.new(store) : SpecConsumers::Notes.new(store)
consumer.start
STDOUT.puts "started"
STDOUT.flush
STDIN.gets
consumer.stop
store.close
