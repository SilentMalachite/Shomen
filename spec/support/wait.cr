# Checks the condition until it holds, for state another process changes
# and nothing in this one can wait on. within only detects a failure
# (docs/decisions/20260929-phase6-process-spec.md).
def wait_until(within : Time::Span = 5.seconds, & : -> Bool) : Nil
  deadline = Time.instant + within
  until yield
    fail "the condition did not hold within #{within}" if Time.instant > deadline
    Fiber.yield
  end
end
