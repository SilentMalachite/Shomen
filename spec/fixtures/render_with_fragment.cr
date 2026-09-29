require "../../src/shomen"

class RenderedFragment < Shomen::Fragment
  def content : Nil
    p "hi"
  end
end

class RenderWithFragment < Shomen::Route
  method GET
  path "/fixture"

  struct Input
  end

  def call(input : Input) : Shomen::Response
    render RenderedFragment.new
  end
end

Shomen::Router.entries
