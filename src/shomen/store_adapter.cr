require "db"
require "./conflict"

# The part of Store that differs by database: the SQL, the column types,
# and how appends wait for each other
# (docs/decisions/20260929-phase6-store-adapters.md).
abstract class Shomen::StoreAdapter
  # type, payload, and at of one event to append.
  alias Row = {String, String, String}
  # id, stream, version, type, and payload of one stored event.
  alias Stored = {Int64, String, Int64, String, String}

  # Each event of a consumer's batch runs inside this savepoint
  # (docs/decisions/20261001-phase7-consumer-batch.md).
  SAVEPOINT          = "SAVEPOINT shomen_event"
  ROLLBACK_SAVEPOINT = "ROLLBACK TO SAVEPOINT shomen_event"
  RELEASE_SAVEPOINT  = "RELEASE SAVEPOINT shomen_event"

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

  # Creates the row of the consumer called name, at checkpoint 0 unless it
  # has one, in one transaction with the tables the block creates
  # (docs/decisions/20261001-phase7-consumer-batch.md).
  abstract def register(name : String, & : DB::Connection ->) : Nil

  # The checkpoint stored for name; 0 when it has none.
  abstract def checkpoint(name : String) : Int64

  # Lends a connection for reads of a consumer's tables.
  abstract def using_connection(& : DB::Connection ->) : Nil

  # Runs one batch of the consumer called name on up to limit events after
  # its checkpoint, in id order. react runs an event's side effects and
  # write its writes, which commit with the new checkpoint. Returns how many
  # events it committed: 0 when there were none, or when another process
  # holds or moved the checkpoint. When an event fails, the events before
  # it commit and the error is raised.
  abstract def consume(name : String, limit : Int32, react : Proc(Stored, Nil), write : Proc(Stored, DB::Connection, Nil)) : Int32

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

  # Runs the block for each row inside the savepoint, until one raises.
  # Returns how many ran, the id of the last, and the error.
  protected def each_in_savepoint(connection : DB::Connection, rows : Array(Stored), & : Stored ->) : {Int32, Int64, Exception?}
    last = 0_i64
    rows.each_with_index do |row, index|
      connection.exec(SAVEPOINT)
      begin
        yield row
      rescue ex
        connection.exec(ROLLBACK_SAVEPOINT)
        connection.exec(RELEASE_SAVEPOINT)
        return {index, last, ex}
      end
      connection.exec(RELEASE_SAVEPOINT)
      last = row[0]
    end
    {rows.size, last, nil}
  end
end
