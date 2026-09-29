require "./event"
require "./rejected"

# An intent. It validates and returns the events to append; it never
# writes. The route appends them with the version it expects.
module Shomen::Command
  abstract def call : Array(Shomen::Event) | Shomen::Rejected
end
