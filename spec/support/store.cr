def remove_database(path : String) : Nil
  [path, "#{path}-wal", "#{path}-shm"].each do |file|
    File.delete(file) if File.exists?(file)
  end
end

def with_store(&) : Nil
  path = File.tempname("shomen-store", ".sqlite3")
  store = Shomen::Store.new("sqlite3://#{path}")
  begin
    yield store, path
  ensure
    store.close
    remove_database(path)
  end
end

def note(text : String) : Array(Shomen::Event)
  [SpecEvents::Noted.new(text)] of Shomen::Event
end
