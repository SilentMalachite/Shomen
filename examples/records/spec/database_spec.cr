require "./spec_helper"

describe "The spec database" do
  it "runs on the database the suite made" do
    url = ENV["RECORDS_DATABASE_URL"]
    if RecordsSpec::ADMIN
      url.should start_with("postgres://")
      url.should contain("/records_spec_")
    else
      url.should start_with("sqlite3://")
    end
  end
end
