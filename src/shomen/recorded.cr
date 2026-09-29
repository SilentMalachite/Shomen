require "./event"

# An event as the store keeps it: its place across every stream (id)
# and within its own stream (version).
struct Shomen::Recorded
  getter id : Int64
  getter stream : String
  getter version : Int64
  getter event : Shomen::Event

  def initialize(@id : Int64, @stream : String, @version : Int64, @event : Shomen::Event)
  end
end
