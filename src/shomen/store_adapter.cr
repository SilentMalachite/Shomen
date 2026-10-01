require "./conflict"

# The part of Store that differs by database: the SQL, the column types,
# and how appends wait for each other
# (docs/decisions/20260929-phase6-store-adapters.md).
abstract class Shomen::StoreAdapter
  # type, payload, and at of one event to append.
  alias Row = {String, String, String}
  # id, stream, version, type, and payload of one stored event.
  alias Stored = {Int64, String, Int64, String, String}

  # Names the database, so every store on it in this process shares one
  # AppendSignal.
  abstract def key : String

  # Appends the rows as the versions after expected_version and returns
  # the id of the last. When the stream is at any other version, appends
  # nothing and raises Shomen::Conflict.
  abstract def append(stream : String, expected_version : Int64, rows : Array(Row)) : Int64

  abstract def read(after : Int64, limit : Int32) : Array(Stored)

  # The highest id in the database, whoever appended it; 0 when it has no
  # event.
  abstract def last_id : Int64

  abstract def close : Nil

  # Whether an append sends a notification that listen receives.
  def notifies? : Bool
    false
  end

  # Waits for notifications and passes on the id each carries, until
  # interrupt_listen ends it or the connection breaks, which raises.
  # Returns at once for a database that sends none.
  def listen(on_id : Int64 -> Nil) : Nil
  end

  # Ends a listen in progress from another fiber.
  def interrupt_listen : Nil
  end

  protected def check_version(stream : String, current : Int64, expected : Int64) : Nil
    unless current == expected
      raise Shomen::Conflict.new("stream #{stream} is at version #{current}, expected #{expected}")
    end
  end
end
