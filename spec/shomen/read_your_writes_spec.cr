require "../spec_helper"

# docs/decisions/20261001-phase7-replica-spec.md

private def get(port : Int32, path : String, cookie : String? = nil) : HTTP::Client::Response
  headers = HTTP::Headers.new
  headers["Cookie"] = cookie if cookie
  HTTP::Client.get("http://127.0.0.1:#{port}#{path}", headers: headers)
end

private def post_form(port : Int32, path : String, cookie : String, form : Hash(String, String)) : HTTP::Client::Response
  headers = HTTP::Headers{"Cookie" => cookie, "Content-Type" => "application/x-www-form-urlencoded"}
  HTTP::Client.post("http://127.0.0.1:#{port}#{path}", headers: headers, body: URI::Params.encode(form))
end

private def form_field(page : HTTP::Client::Response, name : String) : String
  page.body[/name="#{name}" value="([0-9a-f]+)"/, 1]
end

# A new session's cookie and csrf token from the server's token page.
private def open_session(server : Shomen::Server) : {String, String}
  page = call_with(server, "GET", "/phase2/token")
  {session_cookie(page), page.body}
end

private def with_notes(store : Shomen::Store, & : SpecConsumers::Notes ->) : Nil
  notes = SpecConsumers::Notes.new(store)
  ConsumerRoutes.notes = notes
  ConsumerRoutes.store = store
  begin
    yield notes
  ensure
    ConsumerRoutes.notes = nil
    ConsumerRoutes.store = nil
  end
end

describe "read-your-writes with a replica that lags" do
  replica_it "shows the change after a POST to one process, its redirect, and the GET on another" do |primary, replica|
    env = {"SHOMEN_ENV" => "production", "SHOMEN_SECRET" => LONG_SECRET, "WORKER_DATABASE_URL" => primary, "WORKER_REPLICA_URL" => replica}
    store = Shomen::Store.new(primary)
    begin
      store.append("notes", 0_i64, note("copied"))
    ensure
      store.close
    end
    PostgresSpec.copy(primary, replica, "events")
    with_server_process(env: env) do |first|
      with_server_process(env: env) do |second|
        page = get(first.port, "/worker/notes")
        page.body.should contain("<li>copied</li>")
        cookie = session_cookie(page)

        posted = post_form(second.port, "/worker/notes", cookie, {"_csrf" => form_field(page, "_csrf"), "version" => "1", "text" => "after the copy"})
        posted.status_code.should eq(303)
        location = posted.headers["Location"]
        append = append_cookie?(posted) || fail "no shomen_append cookie"

        # Without the append cookie the session sees the replica, which lags.
        get(first.port, location, cookie).body.should_not contain("<li>after the copy</li>")

        [first, second].each do |server|
          body = get(server.port, location, "#{cookie}; #{append}").body
          body.should contain("<li>copied</li>")
          body.should contain("<li>after the copy</li>")
        end
      end
    end
  end

  replica_it "shows the change of a projection kept in tables after a POST, its redirect, and the GET" do |primary, replica|
    store = Shomen::Store.new(replica)
    begin
      SpecConsumers::Notes.new(store).checkpoint
    ensure
      store.close
    end
    store = Shomen::Store.new(primary, replica: replica)
    begin
      with_notes(store) do |notes|
        server = Shomen::Server.new
        cookie, token = open_session(server)
        posted = call_with(server, "POST", "/phase7/notes", cookie, "_csrf=#{token}&text=one")
        posted.status_code.should eq(303)
        append = append_cookie?(posted) || fail "no shomen_append cookie"
        notes.run_once.should eq(1)

        call_with(server, "GET", posted.headers["Location"], cookie).body.should_not contain("<li>one</li>")
        page = call_with(server, "GET", posted.headers["Location"], "#{cookie}; #{append}")
        page.status_code.should eq(200)
        page.body.should contain("<li>one</li>")
      end
    ensure
      store.close
    end
  end
end

describe "a page that reads a projection kept in tables up to the id the session remembers" do
  it "is a 503 document while the consumer lags, and a 200 once the session forgot the id" do
    with_store do |store|
      with_notes(store) do |notes|
        notes.checkpoint
        server = Shomen::Server.new
        cookie, token = open_session(server)
        posted = call_with(server, "POST", "/phase7/notes", cookie, "_csrf=#{token}&text=one")
        posted.status_code.should eq(303)
        append = append_cookie?(posted) || fail "no shomen_append cookie"

        response = call_with(server, "GET", posted.headers["Location"], "#{cookie}; #{append}")
        response.status_code.should eq(503)
        response.body.should contain("<h1>Unavailable</h1>")
        response.body.should_not contain("<ul>")

        sessions = Shomen::SessionStore.new(Shomen::Server.secret_from_env)
        session = sessions.load(cookie.lchop("shomen_session="))
        forgotten = sessions.append_cookie(session, 1_i64, false, Time.utc - Shomen::Session::REMEMBER)
        response = call_with(server, "GET", posted.headers["Location"], "#{cookie}; shomen_append=#{forgotten.value}")
        response.status_code.should eq(200)
        response.body.should_not contain("<li>one</li>")
        call_with(server, "GET", posted.headers["Location"], cookie).status_code.should eq(200)
      end
    end
  end
end
