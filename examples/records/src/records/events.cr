module Items
  struct ItemRegistered
    include Shomen::Event
    event_type "item_registered"

    getter tag : String
    getter name : String
    getter at : Time

    def initialize(@tag : String, @name : String, @at : Time)
    end
  end

  struct ItemLent
    include Shomen::Event
    event_type "item_lent"

    getter tag : String
    getter borrower : String
    getter at : Time

    def initialize(@tag : String, @borrower : String, @at : Time)
    end
  end

  struct ItemReturned
    include Shomen::Event
    event_type "item_returned"

    getter tag : String
    getter at : Time

    def initialize(@tag : String, @at : Time)
    end
  end
end
