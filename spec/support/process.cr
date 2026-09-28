def crystal_build_fixture(path : String) : {Int32, String}
  output = IO::Memory.new
  status = Process.run(
    "crystal",
    ["build", path, "-o", "/tmp/shomen-phase1-fixture", "--error-trace"],
    output: output,
    error: output,
  )
  {status.exit_code || 1, output.to_s}
ensure
  File.delete("/tmp/shomen-phase1-fixture") if File.exists?("/tmp/shomen-phase1-fixture")
end
