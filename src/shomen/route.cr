require "http"
require "uri"

abstract class Shomen::Route
  module Hooks
    macro included
      def self.handle(request : HTTP::Request) : Shomen::Response
        {% verbatim do %}
          {% begin %}
            {% path_node = @type.constant("PATH") %}
            {% if path_node.is_a?(Nop) %}
              {% raise "#{@type.name.stringify} must declare path" %}
            {% end %}
            {% input = @type.constant("Input") %}
            {% unless input.is_a?(TypeNode) %}
              {% raise "#{@type.name.stringify} must declare struct Input" %}
            {% end %}
            {% params = [] of Nil %}
            {% for part in path_node.split("/") %}
              {% if part.starts_with?(":") %}
                {% params << part[1..-1] %}
              {% end %}
            {% end %}
            {% ivars = {} of Nil => Nil %}
            {% for ivar in input.instance_vars %}
              {% ivars[ivar.name.stringify] = ivar.type.stringify %}
            {% end %}
            {% if ivars.size != params.size %}
              {% raise "#{@type.name.stringify} Input must match path params #{params}, found #{ivars.keys}" %}
            {% end %}
            {% for pname in params %}
              {% typ = ivars[pname] %}
              {% unless typ == "Int32" || typ == "Int64" || typ == "String" %}
                {% raise "#{@type.name.stringify} field #{pname} has type #{typ}, want String, Int32, or Int64" %}
              {% end %}
            {% end %}
            captures = ::Shomen::Router.captures!(PATH, request.path)
            input = Input.new(
              {% for pname in params %}
                {{pname.id}}: begin
                  raw = captures[{{pname}}]
                  {% if ivars[pname] == "Int32" %}
                    raw.to_i32?(whitespace: false) || raise ::Shomen::BadInput.new("invalid " + {{pname}})
                  {% elsif ivars[pname] == "Int64" %}
                    raw.to_i64?(whitespace: false) || raise ::Shomen::BadInput.new("invalid " + {{pname}})
                  {% else %}
                    raw
                  {% end %}
                end,
              {% end %}
            )
            new.call(input)
          {% end %}
        {% end %}
      end
    end
  end

  macro inherited
    include Hooks
  end

  macro method(verb)
    {% name = verb.id.stringify %}
    {% unless ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD"].includes?(name) %}
      {% verb.raise "method must be GET, POST, PUT, PATCH, DELETE, or HEAD" %}
    {% end %}
    VERB = {{name}}

    def self.verb : String
      VERB
    end
  end

  macro path(pattern = nil, **kwargs)
    {% if pattern.is_a?(StringLiteral) %}
      {% if kwargs.size != 0 %}
        {% raise "path declaration does not take named arguments" %}
      {% end %}
      {% unless pattern.starts_with?("/") %}
        {% pattern.raise "path must start with /" %}
      {% end %}
      PATH = {{pattern}}

      def self.pattern : String
        PATH
      end
    {% elsif pattern.is_a?(Nop) || pattern.is_a?(NilLiteral) %}
      {% path_node = @type.constant("PATH") %}
      {% if path_node.is_a?(Nop) %}
        {% raise "#{@type.name.stringify} must declare path" %}
      {% end %}
      {% names = [] of Nil %}
      {% for part in path_node.split("/") %}
        {% if part.starts_with?(":") %}
          {% names << part[1..-1] %}
        {% end %}
      {% end %}
      {% if names.empty? %}
        {% if kwargs.size != 0 %}
          {% raise "#{@type.name.stringify}.path takes no arguments" %}
        {% end %}
        {{path_node}}
      {% else %}
        {% if kwargs.size != names.size %}
          {% raise "#{@type.name.stringify}.path arguments must match #{names}" %}
        {% end %}
        {% for pname in names %}
          {% if kwargs[pname].is_a?(Nop) %}
            {% raise "#{@type.name.stringify}.path requires #{pname}" %}
          {% end %}
        {% end %}
        String.build do |%io|
          {% for part, index in path_node.split("/") %}
            {% if part.starts_with?(":") %}
              %component = ({{kwargs[part[1..-1]]}}).to_s
              if %component.includes?("/") || %component.includes?("?") || %component.includes?("#")
                raise ArgumentError.new("invalid path component")
              end
              %io << "/"
              %io << URI.encode_path_segment(%component)
            {% elsif part != "" %}
              %io << "/" << {{part}}
            {% elsif index != 0 %}
              %io << "/"
            {% end %}
          {% end %}
        end
      {% end %}
    {% else %}
      {% pattern.raise "path helper takes named arguments" %}
    {% end %}
  end

  def render(view : Shomen::View) : Shomen::Response
    Shomen::Response.html(view.to_html)
  end

  def redirect(location : String, status : Int32 = 303) : Shomen::Response
    Shomen::Response.redirect(location, status)
  end
end
