module SpecEvents
  struct Noted
    include Shomen::Event
    event_type "spec.noted"

    getter text : String
    getter at : Time

    def initialize(@text : String, @at : Time = Time.utc)
    end
  end

  struct Renamed
    include Shomen::Event
    event_type "spec.renamed"

    getter name : String
    getter at : Time

    def initialize(@name : String, @at : Time = Time.utc)
    end
  end

  struct Note
    include Shomen::Command

    def initialize(@text : String)
    end

    def call : Array(Shomen::Event) | Shomen::Rejected
      return Shomen::Rejected.new(["text must not be empty"]) if @text.empty?
      [Noted.new(@text)] of Shomen::Event
    end
  end
end
