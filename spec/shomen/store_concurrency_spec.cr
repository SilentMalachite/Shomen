require "../spec_helper"

describe "Shomen::Store with concurrent writers" do
  store_it "lets many fibers in one process append at once" do |store, url|
    other = Shomen::Store.new(url)
    begin
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
    ensure
      other.close
    end
  end

  store_it "lets two processes append to one database and a projection see both" do |store, url|
    errors = IO::Memory.new
    worker = Process.new(Workers.binary("spec/support/store_worker.cr"), [url, "worker", "300"], error: errors)
    300.times { |version| store.append("main", version.to_i64, note("main #{version}")) }
    status = worker.wait
    fail "worker failed: #{errors}" unless status.success?

    log = SpecEvents::Log.new(store).catch_up
    log.lines.map(&.id).should eq((1_i64..600_i64).to_a)
    %w(main worker).each do |stream|
      log.lines.select(&.stream.==(stream)).map(&.version).should eq((1_i64..300_i64).to_a)
    end
  end
end
