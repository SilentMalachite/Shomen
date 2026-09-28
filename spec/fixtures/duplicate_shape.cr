require "../../src/shomen"

class ShapeA < Shomen::Route
  method GET
  path "/people/:id"

  struct Input
    getter id : String

    def initialize(@id : String)
    end
  end

  def call(input : Input) : Shomen::Response
    Shomen::Response.html(input.id)
  end
end

class ShapeB < Shomen::Route
  method GET
  path "/people/:name"

  struct Input
    getter name : String

    def initialize(@name : String)
    end
  end

  def call(input : Input) : Shomen::Response
    Shomen::Response.html(input.name)
  end
end

Shomen::Router.entries
