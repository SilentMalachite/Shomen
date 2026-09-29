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

  abstract def close : Nil

  protected def check_version(stream : String, current : Int64, expected : Int64) : Nil
    unless current == expected
      raise Shomen::Conflict.new("stream #{stream} is at version #{current}, expected #{expected}")
    end
  end
end
