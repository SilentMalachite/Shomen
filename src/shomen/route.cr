require "http"
require "json"
require "uri"

abstract class Shomen::Route
  TARGET_HEADER = "Shomen-Target"

  property csrf_token : String = ""
  property target : String? = nil
  # The id this request must not show a state older than: the id the
  # session remembers, raised by remember, or the append an SSE stream woke
  # for. 0 when none (docs/decisions/20261001-phase7-remember-append.md).
  property must_see : Int64 = 0_i64
  getter? remembered : Bool = false

  # The id of the element shomen.js replaces with this response, or nil
  # for a request that did not come from shomen.js. An id is not empty and
  # has no whitespace or comma; two headers are joined with ',' and fail too.
  # HTTP::Headers reads '_' as '-', but Vary does not, so a name such as
  # Shomen_Target fails as well.
  def self.target_of(request : HTTP::Request) : String?
    request.headers.each do |name, _|
      if name.downcase.tr("_", "-") == TARGET_HEADER.downcase && name.compare(TARGET_HEADER, case_insensitive: true) != 0
        raise Shomen::BadInput.new("invalid #{TARGET_HEADER} header")
      end
    end
    value = request.headers[TARGET_HEADER]?
    return nil unless value
    if value.empty? || !value.valid_encoding? || value.includes?(',') || value.each_char.any?(&.ascii_whitespace?)
      raise Shomen::BadInput.new("invalid #{TARGET_HEADER} header")
    end
    value
  end

  module Hooks
    macro included
      def self.handle(request : HTTP::Request, form : URI::Params = URI::Params.new, csrf_token : String = "", must_see : Int64 = 0_i64) : Shomen::Response
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
            {% verb = @type.constant("VERB") %}
            {% reads_form = verb != "GET" && verb != "HEAD" %}
            {% fields = ivars.keys.reject { |name| params.includes?(name) } %}
            {% if params.any? { |name| ivars[name].is_a?(NilLiteral) } || (!reads_form && !fields.empty?) %}
              {% raise "#{@type.name.stringify} Input must match path params #{params}, found #{ivars.keys}" %}
            {% end %}
            {% for name in ivars.keys %}
              {% typ = ivars[name] %}
              {% unless typ == "Int32" || typ == "Int64" || typ == "String" %}
                {% raise "#{@type.name.stringify} field #{name} has type #{typ}, want String, Int32, or Int64" %}
              {% end %}
            {% end %}
            captures = ::Shomen::Router.captures!(PATH, request.path)
            input = Input.new(
              {% for name in ivars.keys %}
                {{name.id}}: begin
                  {% if params.includes?(name) %}
                    raw = captures[{{name}}]
                  {% else %}
                    raw = form[{{name}}]? || raise ::Shomen::BadInput.new("missing " + {{name}})
                  {% end %}
                  {% if ivars[name] == "Int32" %}
                    raw.to_i32?(whitespace: false) || raise ::Shomen::BadInput.new("invalid " + {{name}})
                  {% elsif ivars[name] == "Int64" %}
                    raw.to_i64?(whitespace: false) || raise ::Shomen::BadInput.new("invalid " + {{name}})
                  {% else %}
                    raw
                  {% end %}
                end,
              {% end %}
            )
            route = new
            route.csrf_token = csrf_token
            route.must_see = must_see
            route.target = ::Shomen::Route.target_of(request)
            response = route.call(input)
            response.remember = route.must_see if route.remembered?
            response
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
              # A browser resolves a "." or ".." segment away, so the link would lose it.
              if %component.includes?("/") || %component.includes?("?") || %component.includes?("#") || %component == "." || %component == ".."
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

  # Makes the session remember id, the one an append returned, so its
  # later requests see the state after it. An id that is not positive does
  # nothing.
  def remember(id : Int64) : Nil
    return unless id > 0
    @must_see = id if id > @must_see
    @remembered = true
  end

  def render(view : Shomen::View, status : Int32 = 200) : Shomen::Response
    Shomen::Response.html(view.to_html, status)
  end

  def render(view : Shomen::Fragment, status : Int32 = 200) : Shomen::Response
    {% raise "render takes a document view; send a Shomen::Fragment with render_fragment" %}
  end

  def render_fragment(view : Shomen::Fragment, status : Int32 = 200) : Shomen::Response
    Shomen::Response.html(view.to_html, status)
  end

  def json(value, status : Int32 = 200) : Shomen::Response
    Shomen::Response.new(status, "application/json", value.to_json)
  end

  # Opts this GET route into an event stream for an element with
  # data-shomen-sse. fragment renders now and again after each append to
  # store, through this process or another; the stream sends its HTML
  # whenever it changed. Before each render after an append, must_see
  # becomes that append's id.
  def sse(store : Shomen::Store, heartbeat : Time::Span = Shomen::SSE::HEARTBEAT, &fragment : -> Shomen::Fragment) : Shomen::Response
    route = self
    render = ->(seen : Int64) do
      route.must_see = seen if seen > route.must_see
      fragment.call
    end
    # Crystal types a method by its body, not its return restriction; the cast
    # keeps Router's Proc(..., Shomen::Response) from becoming Proc(..., SSE).
    Shomen::SSE.new(store, render, heartbeat).as(Shomen::Response)
  end

  def redirect(location : String, status : Int32 = 303) : Shomen::Response
    Shomen::Response.redirect(location, status)
  end
end
