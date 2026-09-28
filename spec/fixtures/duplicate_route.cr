require "../../src/shomen"

class DupA < Shomen::Route
  method GET
  path "/dup"

  struct Input
  end

  def call(input : Input) : Shomen::Response
    Shomen::Response.html("a")
  end
end

class DupB < Shomen::Route
  method GET
  path "/dup"

  struct Input
  end

  def call(input : Input) : Shomen::Response
    Shomen::Response.html("b")
  end
end

Shomen::Router.entries
