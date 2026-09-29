require "../../src/shomen/store"
require "../../src/shomen/command"
require "./events"

url, stream, count = ARGV
store = Shomen::Store.new(url)
count.to_i64.times do |version|
  store.append(stream, version, [SpecEvents::Noted.new("#{stream} #{version}")] of Shomen::Event)
end
store.close
