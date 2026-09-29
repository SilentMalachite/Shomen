module SpecEvents
  class Log < Shomen::Projection
    record Line, id : Int64, stream : String, version : Int64, text : String

    getter lines = [] of Line
    property fail_on : String? = nil

    def apply(recorded : Shomen::Recorded) : Nil
      case event = recorded.event
      when Noted
        raise "cannot apply #{event.text}" if event.text == fail_on
        @lines << Line.new(recorded.id, recorded.stream, recorded.version, event.text)
      end
    end
  end
end
