module Users
  struct UserRenamed
    include Shomen::Event
    event_type "user_renamed"

    getter user_id : String
    getter name : String
    getter at : Time

    def initialize(@user_id : String, @name : String, @at : Time)
    end
  end

  struct RenameUser
    include Shomen::Command

    getter user_id : String
    getter name : String

    def initialize(@user_id : String, @name : String)
    end

    def call : Array(Shomen::Event) | Shomen::Rejected
      trimmed = name.strip
      return Shomen::Rejected.new(["Name must be at least 2 characters"]) if trimmed.size < 2
      [UserRenamed.new(user_id, trimmed, Time.utc)] of Shomen::Event
    end
  end

  # The version is the stream's, not the last rename's, so a form opened
  # after any event on the stream expects the version the store checks.
  class Names < Shomen::Projection
    record Entry, name : String, version : Int64

    @names = {} of String => String
    @versions = {} of String => Int64

    def find(user_id : String) : Entry?
      if name = @names[user_id]?
        Entry.new(name, version(user_id))
      end
    end

    def version(user_id : String) : Int64
      @versions[user_id]? || 0_i64
    end

    def apply(recorded : Shomen::Recorded) : Nil
      user_id = recorded.stream.lchop?("user-")
      return unless user_id
      @versions[user_id] = recorded.version
      case event = recorded.event
      when UserRenamed
        @names[user_id] = event.name
      end
    end
  end

  STORE = Shomen::Store.new(ENV["HELLO_DATABASE_URL"]? || "sqlite3://./var/shomen.sqlite3")
  NAMES = Names.new(STORE)

  def self.stream(user_id : String) : String
    "user-#{user_id}"
  end

  class EditView < Shomen::View
    def initialize(@user_id : Int64, @name : String, @version : Int64, @token : String, @error : String?)
    end

    def to_html : String
      user_id = @user_id
      name = @name
      version = @version
      token = @token
      error = @error
      html lang: "en" do
        head do
          title "Rename user"
        end
        body do
          main do
            h1 "Rename user #{user_id}"
            if message = error
              p message
            end
            form(action: Users::Rename.path(id: user_id), method: "post") do
              csrf_field(token)
              input(type: "hidden", name: "version", value: version.to_s)
              label("Name", for: "name")
              input(id: "name", name: "name", type: "text", value: name)
              button "Save", type: "submit"
            end
          end
        end
      end
    end
  end

  class ShowView < Shomen::View
    def initialize(@user_id : Int64, @name : String)
    end

    def to_html : String
      user_id = @user_id
      name = @name
      html lang: "en" do
        head do
          title "User"
        end
        body do
          main do
            h1 name
            a "Rename", href: Users::Edit.path(id: user_id)
          end
        end
      end
    end
  end

  class Edit < Shomen::Route
    method GET
    path "/users/:id/edit"

    struct Input
      getter id : Int64

      def initialize(@id : Int64)
      end
    end

    def call(input : Input) : Shomen::Response
      user_id = input.id.to_s
      NAMES.catch_up
      render EditView.new(input.id, NAMES.find(user_id).try(&.name) || "", NAMES.version(user_id), csrf_token, nil)
    end
  end

  class Rename < Shomen::Route
    method POST
    path "/users/:id"

    struct Input
      getter id : Int64
      getter name : String
      getter version : Int64

      def initialize(@id : Int64, @name : String, @version : Int64)
      end
    end

    def call(input : Input) : Shomen::Response
      raise Shomen::BadInput.new("invalid version") if input.version < 0
      result = RenameUser.new(input.id.to_s, input.name).call
      if result.is_a?(Shomen::Rejected)
        return render EditView.new(input.id, input.name, input.version, csrf_token, result.messages.join(" ")), status: 422
      end
      STORE.append(Users.stream(input.id.to_s), input.version, result)
      redirect Show.path(id: input.id)
    end
  end

  class Show < Shomen::Route
    method GET
    path "/users/:id"

    struct Input
      getter id : Int64

      def initialize(@id : Int64)
      end
    end

    def call(input : Input) : Shomen::Response
      entry = NAMES.catch_up.find(input.id.to_s)
      raise Shomen::NotFound.new unless entry
      render ShowView.new(input.id, entry.name)
    end
  end
end
