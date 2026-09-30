require "uri"
require "./event"
require "./recorded"
require "./append_signal"
require "./store_adapter"
require "./sqlite_adapter"
require "./postgres_adapter"

# The append-only event log. The scheme of the URL picks the database
# (docs/decisions/20260929-phase6-store-adapters.md). After a commit an
# append wakes what waits for it in this process.
class Shomen::Store
  @@signals = {} of String => Shomen::AppendSignal
  @@signals_lock = Mutex.new

  @adapter : Shomen::StoreAdapter
  @signal : Shomen::AppendSignal

  def initialize(url : String)
    uri = begin
      URI.parse(url)
    rescue ex : URI::Error
      raise ArgumentError.new("store URL is not valid: #{ex.message}")
    end
    @adapter = case uri.scheme
               when "sqlite3"
                 Shomen::SQLiteAdapter.new(uri)
               when "postgres", "postgresql"
                 Shomen::PostgresAdapter.new(uri)
               else
                 raise ArgumentError.new("store URL must use sqlite3, postgres, or postgresql, got #{uri.scheme.inspect}")
               end
    key = @adapter.key
    @signal = @@signals_lock.synchronize { @@signals[key] ||= Shomen::AppendSignal.new }
  end

  def append(stream : String, expected_version : Int64, events : Array(Shomen::Event)) : Nil
    raise ArgumentError.new("stream must not be empty") if stream.empty?
    raise ArgumentError.new("expected_version must not be negative") if expected_version < 0
    return if events.empty?
    events.each do |event|
      raise ArgumentError.new("#{event.event_type} at must be UTC, got #{event.at}") unless event.at.utc?
    end
    rows = events.map { |event| {event.event_type, event.to_json, event.at.to_rfc3339} }
    @signal.announce(@adapter.append(stream, expected_version, rows))
  end

  # The highest id this process appended to the database, 0 before the first.
  def last_appended : Int64
    @signal.last
  end

  # Waits until this process appends an event with an id above after.
  # False when within passes first.
  def wait_for_append(after : Int64, within : Time::Span) : Bool
    @signal.wait(after, within)
  end

  def read(after : Int64, limit : Int32 = 500) : Array(Shomen::Recorded)
    @adapter.read(after, limit).map do |row|
      id, stream, version, type, payload = row
      Shomen::Recorded.new(id, stream, version, Shomen::Event.decode(type, payload))
    end
  end

  def close : Nil
    @adapter.close
  end
end
