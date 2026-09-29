require "../spec_helper"

describe "Shomen::Store with concurrent writers" do
  it "lets many fibers in one process append at once" do
    with_store do |store, path|
      other = Shomen::Store.new("sqlite3://#{path}")
      done = Channel(Exception?).new
      fibers = 50
      fibers.times do |fiber|
        target = fiber.even? ? store : other
        spawn do
          10.times { |version| target.append("fiber-#{fiber}", version.to_i64, note("#{fiber}-#{version}")) }
          done.send(nil)
        rescue ex
          done.send(ex)
        end
      end
      failures = Array(Exception?).new(fibers) { done.receive }.compact
      failures.map(&.message).should be_empty
      store.read(after: 0_i64, limit: 1000).size.should eq(500)
      other.close
    end
  end

  it "lets two processes append to one file and a projection see both" do
    binary = File.tempname("shomen-store-worker")
    output = IO::Memory.new
    build = Process.run("crystal", ["build", "spec/support/store_worker.cr", "-o", binary], output: output, error: output)
    fail "worker build failed: #{output}" unless build.success?
    begin
      with_store do |store, path|
        errors = IO::Memory.new
        worker = Process.new(binary, ["sqlite3://#{path}", "worker", "300"], error: errors)
        300.times { |version| store.append("main", version.to_i64, note("main #{version}")) }
        status = worker.wait
        fail "worker failed: #{errors}" unless status.success?

        log = SpecEvents::Log.new(store).catch_up
        log.lines.map(&.id).should eq((1_i64..600_i64).to_a)
        %w(main worker).each do |stream|
          log.lines.select(&.stream.==(stream)).map(&.version).should eq((1_i64..300_i64).to_a)
        end
      end
    ensure
      File.delete(binary) if File.exists?(binary)
      File.delete("#{binary}.dwarf") if File.exists?("#{binary}.dwarf")
    end
  end
end
