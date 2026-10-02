module Items
  class Index < Shomen::Route
    method GET
    path "/items"

    struct Input
    end

    # Read from the same table as call, after the same wait, so a session
    # never gets a 304 for a list older than its own append.
    def validator(input : Input) : String
      Items.last_change(must_see).to_s
    end

    def call(input : Input) : Shomen::Response
      render IndexView.new(ListFragment.new(Items.all(must_see)))
    end
  end

  class Live < Shomen::Route
    method GET
    path "/items/live"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      sse(Records::STORE) { ListFragment.new(Items.all(must_see)) }
    end
  end

  class New < Shomen::Route
    method GET
    path "/items/new"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      render NewView.new("", "", csrf_token, [] of String)
    end
  end

  class Create < Shomen::Route
    method POST
    path "/items"

    struct Input
      getter tag : String
      getter name : String

      def initialize(@tag : String, @name : String)
      end
    end

    # The ledger tells whether the tag is taken; an append that races
    # another registration of it raises Shomen::Conflict, a 409.
    def call(input : Input) : Shomen::Response
      tag = input.tag.strip
      result = RegisterItem.new(tag, input.name, !Items.find(tag, must_see).nil?).call
      if result.is_a?(Shomen::Rejected)
        return render NewView.new(input.tag, input.name, csrf_token, result.messages), status: 422
      end
      remember Records::STORE.append(Items.stream(tag), 0_i64, result)
      redirect Show.path(tag: tag)
    end
  end

  # The item page, which Show renders and Lend and Return send again with
  # a message. A request from shomen.js gets the loan form alone.
  module ItemPage
    private def item_page(item : Item, error : String? = nil, borrower : String = "", status : Int32 = 200) : Shomen::Response
      form_view = LoanFormFragment.new(item, csrf_token, borrower, error)
      return render_fragment(form_view, status: status) if target
      seen = must_see
      history = cached(Records::CACHE, "history", item.tag, item.event_id) { HistoryFragment.new(Items.loans(item.tag, seen)) }
      render ShowView.new(item, form_view, history), status: status
    end

    private def stale(item : Item) : Shomen::Response
      item_page(item, "#{item.tag} changed after this form was shown. Check it and try again.", status: 409)
    end
  end

  class Show < Shomen::Route
    include ItemPage

    method GET
    path "/items/:tag"

    struct Input
      getter tag : String

      def initialize(@tag : String)
      end
    end

    def call(input : Input) : Shomen::Response
      item = Items.find(input.tag, must_see) || raise Shomen::NotFound.new
      item_page(item)
    end
  end

  # Lends at the version the form showed, so it never lends an item whose
  # state changed after the form was opened.
  class Lend < Shomen::Route
    include ItemPage

    method POST
    path "/items/:tag/loans"

    struct Input
      getter tag : String
      getter borrower : String
      getter version : Int64

      def initialize(@tag : String, @borrower : String, @version : Int64)
      end
    end

    def call(input : Input) : Shomen::Response
      item = Items.find(input.tag, must_see) || raise Shomen::NotFound.new
      return stale(item) unless item.version == input.version
      result = LendItem.new(item, input.borrower).call
      if result.is_a?(Shomen::Rejected)
        return item_page(item, result.messages.join(" "), input.borrower, 422)
      end
      remember Records::STORE.append(Items.stream(item.tag), item.version, result)
      redirect Show.path(tag: item.tag)
    end
  end

  class Return < Shomen::Route
    include ItemPage

    method POST
    path "/items/:tag/return"

    struct Input
      getter tag : String
      getter version : Int64

      def initialize(@tag : String, @version : Int64)
      end
    end

    def call(input : Input) : Shomen::Response
      item = Items.find(input.tag, must_see) || raise Shomen::NotFound.new
      return stale(item) unless item.version == input.version
      result = ReturnItem.new(item).call
      return item_page(item, result.messages.join(" "), status: 422) if result.is_a?(Shomen::Rejected)
      remember Records::STORE.append(Items.stream(item.tag), item.version, result)
      redirect Show.path(tag: item.tag)
    end
  end
end
