require "../spec_helper"

private def get(port : Int32, path : String, cookie : String? = nil) : HTTP::Client::Response
  headers = HTTP::Headers.new
  headers["Cookie"] = cookie if cookie
  HTTP::Client.get("http://127.0.0.1:#{port}#{path}", headers: headers)
end

private def post_form(port : Int32, path : String, cookie : String, form : Hash(String, String)) : HTTP::Client::Response
  headers = HTTP::Headers{"Cookie" => cookie, "Content-Type" => "application/x-www-form-urlencoded"}
  HTTP::Client.post("http://127.0.0.1:#{port}#{path}", headers: headers, body: URI::Params.encode(form))
end

describe "two processes with one secret on one Postgres database" do
  postgres_database_it "accept a form one rendered when it is posted to the other, and both show the change" do |url|
    env = {"SHOMEN_ENV" => "production", "SHOMEN_SECRET" => LONG_SECRET, "WORKER_DATABASE_URL" => url}
    with_server_process(env: env) do |first|
      with_server_process(env: env) do |second|
        page = get(first.port, "/worker/notes")
        page.status_code.should eq(200)
        cookie = session_cookie(page)
        token = page.body[/name="_csrf" value="([0-9a-f]+)"/, 1]
        version = page.body[/name="version" value="(\d+)"/, 1]

        posted = post_form(second.port, "/worker/notes", cookie, {"_csrf" => token, "version" => version, "text" => "sent to the other"})
        posted.status_code.should eq(303)

        [first, second].each do |server|
          get(server.port, "/worker/notes", cookie).body.should contain("<li>sent to the other</li>")
        end
      end
    end
  end
end
