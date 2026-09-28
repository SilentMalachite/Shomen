require "../spec_helper"

private def post(path : String) : HTTP::Request
  HTTP::Request.new("POST", path)
end

describe "form input" do
  it "binds form fields to Input" do
    response = ServerRoutes::Signup.handle(post("/phase2/signup"), URI::Params.parse("name=Ada&age=36"), "t")
    response.body.should eq("Ada:36")
  end

  it "binds a path parameter and a form field together" do
    response = ServerRoutes::Rename.handle(post("/phase2/people/7"), URI::Params.parse("name=Ada"), "t")
    response.body.should eq("7:Ada")
  end

  it "decodes plus signs and percent escapes" do
    response = ServerRoutes::Signup.handle(post("/phase2/signup"), URI::Params.parse("name=Ada+L%C3%B6v&age=36"), "t")
    response.body.should eq("Ada Löv:36")
  end

  it "uses the first value of a repeated field" do
    response = ServerRoutes::Signup.handle(post("/phase2/signup"), URI::Params.parse("name=Ada&name=Bob&age=36"), "t")
    response.body.should eq("Ada:36")
  end

  it "ignores fields that Input does not declare" do
    response = ServerRoutes::Signup.handle(post("/phase2/signup"), URI::Params.parse("_csrf=x&extra=1&name=Ada&age=36"), "t")
    response.body.should eq("Ada:36")
  end

  it "raises BadInput for a missing field" do
    expect_raises(Shomen::BadInput, "missing age") do
      ServerRoutes::Signup.handle(post("/phase2/signup"), URI::Params.parse("name=Ada"), "t")
    end
  end

  it "raises BadInput for a field that is not an integer" do
    ["abc", " 36", ""].each do |age|
      expect_raises(Shomen::BadInput, "invalid age") do
        ServerRoutes::Signup.handle(post("/phase2/signup"), URI::Params.new({"name" => ["Ada"], "age" => [age]}), "t")
      end
    end
  end

  it "hands the csrf token to the route" do
    ServerRoutes::Token.handle(HTTP::Request.new("GET", "/phase2/token"), URI::Params.new, "tok").body.should eq("tok")
  end

  it "returns 400 HTML through the server for a missing field" do
    server = Shomen::Server.new
    token_response = call_with(server, "GET", "/phase2/token")
    cookie = session_cookie(token_response)
    body = URI::Params.encode({"_csrf" => token_response.body, "name" => "Ada"})
    response = call_with(server, "POST", "/phase2/signup", cookie: cookie, body: body)
    response.status_code.should eq(400)
    response.body.should contain("missing age")
  end

  it "rejects a GET route whose Input has a field outside the path" do
    status, output = crystal_build_fixture("spec/fixtures/route_get_form_field.cr")
    status.should_not eq(0)
    output.should contain("must match path params")
  end

  it "rejects a form field type outside String, Int32, and Int64" do
    status, output = crystal_build_fixture("spec/fixtures/route_form_bad_type.cr")
    status.should_not eq(0)
    output.should contain("String, Int32, or Int64")
  end
end
