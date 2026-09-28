class Shomen::Session
  COOKIE = "shomen_session"

  getter id : String
  getter? fresh : Bool
  getter csrf_token : String

  def initialize(@id : String, @fresh : Bool, @csrf_token : String)
  end
end
