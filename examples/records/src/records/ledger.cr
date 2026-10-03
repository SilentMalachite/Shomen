module Items
  # An item as the ledger keeps it. version is its stream's, and event_id
  # the id of the last event that changed it.
  record Item, tag : String, name : String, borrower : String?, version : Int64, event_id : Int64 do
    def lent? : Bool
      !borrower.nil?
    end
  end

  # One loan, newest first in a history. The times are RFC 3339.
  record Loan, borrower : String, lent_at : String, returned_at : String?

  def self.stream(tag : String) : String
    "item-#{tag}"
  end

  # Keeps records_items, a row per item, and records_loans, a row per
  # loan (docs/decisions/20261003-phase8-records.md).
  class Ledger < Shomen::Consumer
    def name : String
      "records_ledger"
    end

    def create_tables(connection : DB::Connection) : Nil
      connection.exec("CREATE TABLE IF NOT EXISTS records_items (tag TEXT PRIMARY KEY, name TEXT NOT NULL, borrower TEXT, version BIGINT NOT NULL, event_id BIGINT NOT NULL)")
      connection.exec("CREATE TABLE IF NOT EXISTS records_loans (event_id BIGINT PRIMARY KEY, tag TEXT NOT NULL, borrower TEXT NOT NULL, lent_at TEXT NOT NULL, returned_at TEXT)")
    end

    def write(recorded : Shomen::Recorded, connection : DB::Connection) : Nil
      case event = recorded.event
      when ItemRegistered
        connection.exec("INSERT INTO records_items (tag, name, borrower, version, event_id) VALUES ($1, $2, NULL, $3, $4)", event.tag, event.name, recorded.version, recorded.id)
      when ItemLent
        connection.exec("UPDATE records_items SET borrower = $1, version = $2, event_id = $3 WHERE tag = $4", event.borrower, recorded.version, recorded.id, event.tag)
        connection.exec("INSERT INTO records_loans (event_id, tag, borrower, lent_at, returned_at) VALUES ($1, $2, $3, $4, NULL)", recorded.id, event.tag, event.borrower, event.at.to_rfc3339)
      when ItemReturned
        connection.exec("UPDATE records_items SET borrower = NULL, version = $1, event_id = $2 WHERE tag = $3", recorded.version, recorded.id, event.tag)
        connection.exec("UPDATE records_loans SET returned_at = $1 WHERE tag = $2 AND returned_at IS NULL", event.at.to_rfc3339, event.tag)
      end
    end
  end

  # The item once the ledger reached seen, or nil when it has no such tag.
  def self.find(tag : String, seen : Int64) : Item?
    row = Records::LEDGER.read(seen) do |connection|
      connection.query_one?("SELECT tag, name, borrower, version, event_id FROM records_items WHERE tag = $1", tag, as: {String, String, String?, Int64, Int64})
    end
    row.try { |values| Item.new(*values) }
  end

  def self.all(seen : Int64) : Array(Item)
    rows = Records::LEDGER.read(seen) do |connection|
      connection.query_all("SELECT tag, name, borrower, version, event_id FROM records_items ORDER BY tag", as: {String, String, String?, Int64, Int64})
    end
    rows.map { |values| Item.new(*values) }
  end

  # The item and its loans, newest first, from one statement, so the
  # history always belongs to the item's event_id, even when the ledger
  # moves on between reads or a read falls back from replica to primary.
  def self.find_with_loans(tag : String, seen : Int64) : {Item, Array(Loan)}?
    rows = Records::LEDGER.read(seen) do |connection|
      connection.query_all("SELECT i.tag, i.name, i.borrower, i.version, i.event_id, l.borrower, l.lent_at, l.returned_at FROM records_items i LEFT JOIN records_loans l ON l.tag = i.tag WHERE i.tag = $1 ORDER BY l.event_id DESC", tag, as: {String, String, String?, Int64, Int64, String?, String?, String?})
    end
    first = rows.first? || return nil
    item = Item.new(first[0], first[1], first[2], first[3], first[4])
    loans = rows.compact_map do |row|
      borrower, lent_at = row[5], row[6]
      Loan.new(borrower, lent_at, row[7]) if borrower && lent_at
    end
    {item, loans}
  end

  # The id of the last event the ledger applied to any of items, so it
  # changes with every append the list shows.
  def self.last_change(items : Array(Item)) : Int64
    items.max_of?(&.event_id) || 0_i64
  end
end
