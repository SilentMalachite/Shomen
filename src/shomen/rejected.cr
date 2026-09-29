# What a command returns instead of events when its input is invalid.
# The messages are shown to the person who sent the input.
struct Shomen::Rejected
  getter messages : Array(String)

  def initialize(@messages : Array(String))
  end
end
