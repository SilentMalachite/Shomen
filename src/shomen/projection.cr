require "./store"
require "./recorded"

# A read model built by applying events in id order. The checkpoint is
# the last id applied, so a catch_up sees events any process appended.
abstract class Shomen::Projection
  BATCH = 500

  getter checkpoint : Int64 = 0_i64
  @lock = Mutex.new

  def initialize(@store : Shomen::Store)
  end

  abstract def apply(recorded : Shomen::Recorded) : Nil

  def catch_up : self
    @lock.synchronize do
      loop do
        batch = @store.read(after: @checkpoint, limit: BATCH)
        batch.each do |recorded|
          apply(recorded)
          @checkpoint = recorded.id
        end
        break if batch.size < BATCH
      end
    end
    self
  end
end
