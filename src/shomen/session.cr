class Shomen::Session
  COOKIE = "shomen_session"

  getter id : String
  getter? fresh : Bool
  getter csrf_token : String
  # Only SHOMEN_SECRET_VERIFY verified the cookie, so the response sends
  # it again under SHOMEN_SECRET.
  getter? reissue : Bool

  def initialize(@id : String, @fresh : Bool, @csrf_token : String, @reissue : Bool = false)
  end
end
