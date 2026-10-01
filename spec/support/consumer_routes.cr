# Pages that read SpecConsumers::Notes once its checkpoint reached the id
# in the path or the one the session remembers, waiting at most 50 ms, and
# a form that appends a note. A spec sets the consumer and the store.
module ConsumerRoutes
  @@notes : SpecConsumers::Notes? = nil
  @@store : Shomen::Store? = nil

  def self.notes=(notes : SpecConsumers::Notes?) : Nil
    @@notes = notes
  end

  def self.notes! : SpecConsumers::Notes
    @@notes || raise "set ConsumerRoutes.notes first"
  end

  def self.store=(store : Shomen::Store?) : Nil
    @@store = store
  end

  def self.store! : Shomen::Store
    @@store || raise "set ConsumerRoutes.store first"
  end

  def self.texts(seen : Int64) : Array(String)
    notes!.read(seen, within: 50.milliseconds) do |connection|
      connection.query_all("SELECT text FROM spec_notes ORDER BY event_id", as: String)
    end
  end

  class NotesView < Shomen::View
    def initialize(@texts : Array(String))
    end

    def to_html : String
      texts = @texts
      html lang: "en" do
        head do
          title "Notes"
        end
        body do
          main do
            ul do
              texts.each { |text| li text }
            end
          end
        end
      end
    end
  end

  class Show < Shomen::Route
    method GET
    path "/phase7/notes/:seen"

    struct Input
      getter seen : Int64

      def initialize(@seen : Int64)
      end
    end

    def call(input : Input) : Shomen::Response
      render NotesView.new(ConsumerRoutes.texts(input.seen))
    end
  end

  # Reads up to the id the session remembers.
  class Remembered < Shomen::Route
    method GET
    path "/phase7/notes"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      render NotesView.new(ConsumerRoutes.texts(must_see))
    end
  end

  # Appends a note to a stream of its own and remembers it.
  class Add < Shomen::Route
    method POST
    path "/phase7/notes"

    struct Input
      getter text : String

      def initialize(@text : String)
      end
    end

    def call(input : Input) : Shomen::Response
      remember ConsumerRoutes.store!.append("note-#{input.text}", 0_i64, [SpecEvents::Noted.new(input.text)] of Shomen::Event)
      redirect Remembered.path
    end
  end
end
