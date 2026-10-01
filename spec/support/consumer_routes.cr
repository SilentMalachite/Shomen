# A page that reads SpecConsumers::Notes once its checkpoint reached the id
# in the path, waiting at most 50 ms. A spec sets the consumer.
module ConsumerRoutes
  @@notes : SpecConsumers::Notes? = nil

  def self.notes=(notes : SpecConsumers::Notes?) : Nil
    @@notes = notes
  end

  def self.notes! : SpecConsumers::Notes
    @@notes || raise "set ConsumerRoutes.notes first"
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
      texts = ConsumerRoutes.notes!.read(input.seen, within: 50.milliseconds) do |connection|
        connection.query_all("SELECT text FROM spec_notes ORDER BY event_id", as: String)
      end
      render NotesView.new(texts)
    end
  end
end
