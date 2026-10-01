class Shomen::Session
  COOKIE = "shomen_session"
  # Holds the id of the session's last append for REMEMBER
  # (docs/decisions/20261001-phase7-remember-append.md).
  APPEND_COOKIE = "shomen_append"
  REMEMBER      = 60.seconds

  getter id : String
  getter? fresh : Bool
  getter csrf_token : String
  # Only SHOMEN_SECRET_VERIFY verified the cookie, so the response sends
  # it again under SHOMEN_SECRET.
  getter? reissue : Bool
  # The id of the last append the session remembers, 0 when none.
  getter remembered : Int64

  def initialize(@id : String, @fresh : Bool, @csrf_token : String, @reissue : Bool = false, @remembered : Int64 = 0_i64)
  end
end
