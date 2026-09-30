# Builds a spec worker once per run; the suite removes the binaries at the
# end (docs/decisions/20260929-phase6-process-spec.md).
module Workers
  @@binaries = {} of String => String

  def self.binary(source : String) : String
    @@binaries[source] ||= begin
      binary = File.tempname("shomen-worker")
      output = IO::Memory.new
      status = Process.run("crystal", ["build", source, "-o", binary], output: output, error: output)
      raise "#{source} did not build: #{output}" unless status.success?
      binary
    end
  end

  def self.remove : Nil
    @@binaries.each_value do |binary|
      [binary, "#{binary}.dwarf"].each { |file| File.delete(file) if File.exists?(file) }
    end
  end
end
