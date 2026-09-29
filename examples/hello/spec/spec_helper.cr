require "spec"
ENV["SHOMEN_SPEC"] = "1"
ENV["SHOMEN_SECRET"] = "spec-secret"
HELLO_DATABASE = File.tempname("hello", ".sqlite3")
ENV["HELLO_DATABASE_URL"] = "sqlite3://#{HELLO_DATABASE}"
require "../src/hello"

Spec.after_suite do
  Users::STORE.close
  [HELLO_DATABASE, "#{HELLO_DATABASE}-wal", "#{HELLO_DATABASE}-shm"].each do |file|
    File.delete(file) if File.exists?(file)
  end
end
