module Items
  struct RegisterItem
    include Shomen::Command

    # A path helper refuses /, ?, #, . and .., so a tag cannot hold them.
    TAG          = /\A[A-Z0-9][A-Z0-9-]{0,19}\z/
    TAG_MESSAGE  = "Tag must be 1 to 20 capital letters, digits, or hyphens, and start with a letter or digit"
    NAME_LIMIT   = 80
    NAME_MESSAGE = "Name must be 1 to #{NAME_LIMIT} characters"

    getter tag : String
    getter name : String

    # registered tells whether the ledger has the tag.
    def initialize(@tag : String, @name : String, @registered : Bool)
    end

    def call : Array(Shomen::Event) | Shomen::Rejected
      trimmed = name.strip
      messages = [] of String
      messages << TAG_MESSAGE unless TAG.matches?(tag)
      messages << NAME_MESSAGE unless (1..NAME_LIMIT).includes?(trimmed.size)
      messages << "#{tag} is already registered" if @registered
      return Shomen::Rejected.new(messages) unless messages.empty?
      [ItemRegistered.new(tag, trimmed, Time.utc)] of Shomen::Event
    end
  end

  struct LendItem
    include Shomen::Command

    BORROWER_MESSAGE = "Borrower must be 1 to #{RegisterItem::NAME_LIMIT} characters"

    def initialize(@item : Item, @borrower : String)
    end

    def call : Array(Shomen::Event) | Shomen::Rejected
      if holder = @item.borrower
        return Shomen::Rejected.new(["#{@item.tag} is lent to #{holder}. Record its return first"])
      end
      borrower = @borrower.strip
      return Shomen::Rejected.new([BORROWER_MESSAGE]) unless (1..RegisterItem::NAME_LIMIT).includes?(borrower.size)
      [ItemLent.new(@item.tag, borrower, Time.utc)] of Shomen::Event
    end
  end

  struct ReturnItem
    include Shomen::Command

    def initialize(@item : Item)
    end

    def call : Array(Shomen::Event) | Shomen::Rejected
      return Shomen::Rejected.new(["#{@item.tag} is not lent"]) unless @item.lent?
      [ItemReturned.new(@item.tag, Time.utc)] of Shomen::Event
    end
  end
end
