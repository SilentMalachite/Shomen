module SpecConsumers
  # Keeps one row per Noted event in the table it is named after. Each row
  # holds the highest event id in the table before it, so a spec sees
  # whether the events were applied once and in id order. An event whose
  # text is fail_react or fail_write fails in that step, after its row is
  # written in the case of write, failures times.
  class Notes < Shomen::Consumer
    property fail_react : String? = nil
    property fail_write : String? = nil
    property failures : Int32 = Int32::MAX
    property on_react : Proc(Shomen::Recorded, Nil)? = nil
    getter reacted = [] of String

    def initialize(store : Shomen::Store, @table : String = "spec_notes", retry_first : Time::Span = 10.milliseconds, retry_limit : Time::Span = 1.second)
      super(store, retry_first, retry_limit)
    end

    def name : String
      @table
    end

    def create_tables(connection : DB::Connection) : Nil
      connection.exec("CREATE TABLE IF NOT EXISTS #{@table} (event_id BIGINT NOT NULL, text TEXT NOT NULL, max_before BIGINT NOT NULL)")
    end

    def react(recorded : Shomen::Recorded) : Nil
      @on_react.try &.call(recorded)
      event = recorded.event
      return unless event.is_a?(SpecEvents::Noted)
      fail_once("react", event.text) if event.text == fail_react
      @reacted << event.text
    end

    def write(recorded : Shomen::Recorded, connection : DB::Connection) : Nil
      event = recorded.event
      return unless event.is_a?(SpecEvents::Noted)
      before = connection.scalar("SELECT COALESCE(MAX(event_id), 0) FROM #{@table}").as(Int64)
      connection.exec("INSERT INTO #{@table} (event_id, text, max_before) VALUES ($1, $2, $3)", recorded.id, event.text, before)
      fail_once("write", event.text) if event.text == fail_write
    end

    # The texts in the table in id order, whatever the checkpoint.
    def texts : Array(String)
      @store.using_connection do |connection|
        connection.query_all("SELECT text FROM #{@table} ORDER BY event_id", as: String)
      end
    end

    private def fail_once(step : String, text : String) : Nil
      return unless @failures > 0
      @failures -= 1
      raise "cannot #{step} #{text}"
    end
  end
end
