require "../../src/shomen"

struct Unnamed
  include Shomen::Event

  getter at : Time

  def initialize(@at : Time)
  end
end

Unnamed.new(Time.utc).to_json
