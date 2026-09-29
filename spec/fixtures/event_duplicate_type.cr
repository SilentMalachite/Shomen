require "../../src/shomen"

struct First
  include Shomen::Event
  event_type "same"

  getter at : Time

  def initialize(@at : Time)
  end
end

struct Second
  include Shomen::Event
  event_type "same"

  getter at : Time

  def initialize(@at : Time)
  end
end

First.new(Time.utc).to_json
