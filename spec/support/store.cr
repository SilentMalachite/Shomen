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

STORE_KINDS = {"sqlite3", "postgres"}

# Yields the URL of a new, empty database of kind and removes it afterwards.
def with_store_url(kind : String, & : String ->) : Nil
  if kind == "postgres"
    PostgresSpec.with_database { |url| yield url }
  else
    path = File.tempname("shomen-store", ".sqlite3")
    begin
      yield "sqlite3://#{path}"
    ensure
      remove_database(path)
    end
  end
end

# One example per kind of store, each on a new database; the Postgres one
# is pending without SHOMEN_SPEC_POSTGRES
# (docs/decisions/20260929-phase6-postgres-spec.md).
def store_it(description : String, file = __FILE__, line = __LINE__, &block : Shomen::Store, String ->) : Nil
  STORE_KINDS.each { |kind| store_example(kind, "#{description} (#{kind})", file, line, block) }
end

def postgres_it(description : String, file = __FILE__, line = __LINE__, &block : Shomen::Store, String ->) : Nil
  store_example("postgres", description, file, line, block)
end

private def store_example(kind : String, description : String, file : String, line : Int32, block : Shomen::Store, String ->) : Nil
  if kind == "postgres" && PostgresSpec.admin_url.nil?
    pending(description, file, line) { }
    return
  end
  it(description, file, line) do
    with_store_url(kind) do |url|
      store = Shomen::Store.new(url)
      begin
        block.call(store, url)
      ensure
        store.close
      end
    end
  end
end
