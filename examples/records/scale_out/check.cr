require "./two_processes"

# bin/check FIRST_ORIGIN SECOND_ORIGIN, as docs/en/05-SCALE-OUT.md runs it.
abort "usage: bin/check FIRST_ORIGIN SECOND_ORIGIN" unless ARGV.size == 2
first = URI.parse(ARGV[0])
second = URI.parse(ARGV[1])
begin
  TwoProcesses.run(first, second)
  puts "two processes: an item registered through #{first} reached the pages and the stream of #{second}"
rescue error : TwoProcesses::Failed
  abort "two processes: #{error.message}"
end
