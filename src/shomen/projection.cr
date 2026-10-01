require "./store"
require "./recorded"

# A read model built by applying events in id order. The checkpoint is
# the last id applied, so a catch_up sees events any process appended.
abstract class Shomen::Projection
  BATCH = 500

  # docs/decisions/20261001-phase7-replica.md
  WAIT        = 2.seconds
  CHECK_FIRST = 10.milliseconds
  CHECK_LIMIT = 200.milliseconds

  getter checkpoint : Int64 = 0_i64
  @lock = Mutex.new

  def initialize(@store : Shomen::Store)
  end

  abstract def apply(recorded : Shomen::Recorded) : Nil

  # Applies the events after the checkpoint. A store with a replica reads
  # it, and while the checkpoint is below id, reads it again, after
  # CHECK_FIRST, then twice as long each time, at most CHECK_LIMIT. When
  # within passes first, it catches up from the primary, which has every
  # append. The lock is not held between the reads.
  def catch_up(id : Int64 = 0_i64, within : Time::Span = WAIT) : self
    return apply_after(replica: false) unless @store.replica?
    deadline = Time.instant + within
    check = CHECK_FIRST
    loop do
      apply_after(replica: true)
      return self if checkpoint >= id
      left = deadline - Time.instant
      break unless left.positive?
      sleep({check, left}.min)
      check = {check * 2, CHECK_LIMIT}.min
    end
    apply_after(replica: false)
  end

  private def apply_after(replica : Bool) : self
    @lock.synchronize do
      loop do
        batch = @store.read(after: @checkpoint, limit: BATCH, replica: replica)
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
