require "json"

# A fact. Stored rows are never rewritten, so each type keeps the name it
# declares with event_type, even after the Crystal type is renamed.
module Shomen::Event
  macro included
    include JSON::Serializable
  end

  macro event_type(name)
    {% unless name.is_a?(StringLiteral) && !name.empty? %}
      {% name.raise "event_type takes a non-empty string literal" %}
    {% end %}
    EVENT_TYPE = {{name}}

    def event_type : String
      EVENT_TYPE
    end
  end

  abstract def event_type : String
  abstract def at : Time

  def self.decode(type : String, payload : String) : Shomen::Event
    {% begin %}
      {% events = Shomen::Event.includers %}
      {% if events.empty? %}
        raise ArgumentError.new("unknown event type #{type.inspect}")
      {% else %}
        case type
        {% for event in events %}
          when {{event}}::EVENT_TYPE then {{event}}.from_json(payload)
        {% end %}
        else
          raise ArgumentError.new("unknown event type #{type.inspect}")
        end
      {% end %}
    {% end %}
  end

  macro finished
    {% seen = {} of Nil => Nil %}
    {% for event in @type.includers %}
      {% unless event.has_constant?("EVENT_TYPE") %}
        {% raise "#{event.name} must declare event_type" %}
      {% end %}
      {% name = event.constant("EVENT_TYPE") %}
      {% if seen[name] %}
        {% raise "#{event.name} and #{seen[name]} both declare event_type #{name}" %}
      {% end %}
      {% seen[name] = event.name %}
    {% end %}
  end
end
