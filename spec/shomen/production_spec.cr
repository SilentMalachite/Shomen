require "../spec_helper"

describe "SHOMEN_ENV=production" do
  it "refuses to start without SHOMEN_SECRET and names the variable" do
    with_env({"SHOMEN_ENV" => "production", "SHOMEN_SECRET" => nil}) do
      expect_raises(ArgumentError, "SHOMEN_SECRET must be set to at least 32 bytes when SHOMEN_ENV=production") do
        Shomen::Server.new
      end
    end
  end

  it "refuses a SHOMEN_SECRET shorter than 32 bytes and takes one of 32" do
    with_env({"SHOMEN_ENV" => "production", "SHOMEN_SECRET" => "x" * 31}) do
      expect_raises(ArgumentError, "SHOMEN_SECRET") { Shomen::Server.new }
    end
    with_env({"SHOMEN_ENV" => "production", "SHOMEN_SECRET" => "x" * 32}) do
      Shomen::Server.new.should be_a(Shomen::Server)
    end
  end

  it "refuses a short secret passed directly" do
    with_env({"SHOMEN_ENV" => "production"}) do
      expect_raises(ArgumentError, "secret must be at least 32 bytes when SHOMEN_ENV=production") do
        Shomen::Server.new(secret: "short")
      end
    end
  end

  it "reads only the value production as production" do
    with_env({"SHOMEN_ENV" => "Production"}) do
      Shomen::Server.production?.should be_false
      Shomen::Server.new(secret: "short").should be_a(Shomen::Server)
    end
  end

  it "hides the exception message and logs the exception" do
    with_env({"SHOMEN_ENV" => "production"}) do
      Log.capture("shomen") do |logs|
        response = call_with(Shomen::Server.new(secret: LONG_SECRET), "GET", "/phase1/boom")
        response.status_code.should eq(500)
        response.body.should contain("<title>Error</title>")
        response.body.should_not contain("boom")
        logs.check(:error, "unhandled exception")
        logs.entry.exception.try(&.message).should eq("boom <script>")
      end
    end
  end

  it "still explains bad input" do
    with_env({"SHOMEN_ENV" => "production"}) do
      response = call_with(Shomen::Server.new(secret: LONG_SECRET), "GET", "/phase1/bad/abc")
      response.status_code.should eq(400)
      response.body.should contain("invalid id")
    end
  end

  it "refuses a SHOMEN_SECRET_VERIFY shorter than 32 bytes and names it" do
    with_env({"SHOMEN_ENV" => "production", "SHOMEN_SECRET" => LONG_SECRET, "SHOMEN_SECRET_VERIFY" => "x" * 31}) do
      expect_raises(ArgumentError, "SHOMEN_SECRET_VERIFY must be at least 32 bytes when SHOMEN_ENV=production") do
        Shomen::Server.new
      end
    end
  end

  it "refuses a short verify secret passed directly" do
    with_env({"SHOMEN_ENV" => "production"}) do
      expect_raises(ArgumentError, "verify_secret must be at least 32 bytes when SHOMEN_ENV=production") do
        Shomen::Server.new(secret: LONG_SECRET, verify_secret: "short")
      end
    end
  end
end
