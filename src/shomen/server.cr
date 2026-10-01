require "http/server"
require "http/server/handler"
require "random/secure"
require "log"

class Shomen::Server
  include HTTP::Handler

  UNSAFE_METHODS  = {"POST", "PUT", "PATCH", "DELETE"}
  FORM_TYPE       = "application/x-www-form-urlencoded"
  CSRF_FIELD      = "_csrf"
  MAX_FORM_BYTES  = 1_048_576
  CONFLICT_DETAIL = "This changed after the page was loaded. Reload the page and try again."
  # docs/decisions/20261001-phase7-consumer-read.md
  UNAVAILABLE_DETAIL = "This page cannot show the latest changes yet. Try again in a moment."
  # docs/decisions/20260929-phase6-csp.md
  CSP              = "default-src 'self'; base-uri 'none'; form-action 'self'; frame-ancestors 'none'; object-src 'none'"
  MIN_SECRET_BYTES = 32
  # Inside the 30 seconds Kubernetes waits before SIGKILL.
  SHUTDOWN_TIMEOUT = 25.seconds

  Log = ::Log.for("shomen")

  @@generated_secret : String?

  getter connections = Shomen::Connections.new

  # Serves until SIGTERM or SIGINT. Then it stops accepting, closes idle
  # connections and SSE streams, and returns once the requests in progress
  # finish or shutdown_timeout passes. A second signal ends the process at
  # once (docs/decisions/20260929-phase6-shutdown.md).
  def self.start(host : String = "127.0.0.1", port : Int32 = 3000, https : Bool = false, reuse_port : Bool = false, shutdown_timeout : Time::Span = SHUTDOWN_TIMEOUT) : Nil
    Shomen::Router.entries
    server = new(https: https)
    listener = Shomen::Listener.new(server.connections, server)
    address = listener.bind_tcp(host, port, reuse_port: reuse_port)
    # The first run puts TERM and INT back to the kernel's default action
    # with LibC.signal, not Signal#reset, so a later signal ends the process
    # at once even while the event loop is stalled, and Crystal's handlers
    # stay registered: a signal already in the signal pipe still finds one
    # (a missing one is fatal). That run puts its signal back to the default
    # action and sends it again, so the process ends by that signal.
    stopping = Atomic(Bool).new(false)
    {Signal::TERM, Signal::INT}.each do |signal|
      signal.trap do |received|
        if stopping.swap(true)
          received.reset
          Process.signal(received, Process.pid)
        else
          LibC.signal(Signal::TERM.value, LibC::SIG_DFL)
          LibC.signal(Signal::INT.value, LibC::SIG_DFL)
          server.connections.drain
          listener.close
          STDERR.puts "shomen: shutting down"
        end
      end
    end
    STDERR.puts "shomen: listening on http://#{address}"
    listener.listen
    server.connections.wait(shutdown_timeout)
  end

  # SHOMEN_ENV=production, read when a server is made
  # (docs/decisions/20260929-phase6-production.md).
  def self.production? : Bool
    ENV["SHOMEN_ENV"]? == "production"
  end

  # The one 32-byte rule for every production secret; `name` is what the
  # error message names (SHOMEN_SECRET, SHOMEN_SECRET_VERIFY, ...).
  protected def self.check_length(name : String, value : String) : Nil
    if value.bytesize < MIN_SECRET_BYTES
      raise ArgumentError.new("#{name} must be at least #{MIN_SECRET_BYTES} bytes when SHOMEN_ENV=production")
    end
  end

  def self.secret_from_env : String
    secret = ENV["SHOMEN_SECRET"]?.presence
    if production?
      unless secret
        raise ArgumentError.new("SHOMEN_SECRET must be set to at least #{MIN_SECRET_BYTES} bytes when SHOMEN_ENV=production")
      end
      check_length("SHOMEN_SECRET", secret)
      return secret
    end
    return secret if secret
    @@generated_secret ||= begin
      STDERR.puts "shomen: SHOMEN_SECRET is not set; using a random secret until restart"
      Random::Secure.hex(32)
    end
  end

  def self.verify_secret_from_env : String?
    secret = ENV["SHOMEN_SECRET_VERIFY"]?.presence
    check_length("SHOMEN_SECRET_VERIFY", secret) if secret && production?
    secret
  end

  def initialize(secret : String = Shomen::Server.secret_from_env, verify_secret : String? = Shomen::Server.verify_secret_from_env, @https : Bool = false)
    @sessions = Shomen::SessionStore.new(secret, verify_secret)
    @production = Shomen::Server.production?
    if @production
      Shomen::Server.check_length("secret", secret)
      Shomen::Server.check_length("verify_secret", verify_secret) if verify_secret
    end
  end

  def call(context : HTTP::Server::Context) : Nil
    @connections.request do
      cookies = context.request.cookies
      session = @sessions.load(cookies[Shomen::Session::COOKIE]?.try(&.value), cookies[Shomen::Session::APPEND_COOKIE]?.try(&.value))
      write_response(context, respond(context.request, session), session)
    end
  end

  def dispatch(request : HTTP::Request, form : URI::Params = URI::Params.new, csrf_token : String = "", must_see : Int64 = 0_i64) : Shomen::Response
    handler = Shomen::Router.find(request.method, request.path)
    return error_response(404, "Not found", nil) unless handler
    handler.call(request, form, csrf_token, must_see)
  end

  private def respond(request : HTTP::Request, session : Shomen::Session) : Shomen::Response
    form = read_form(request)
    return error_response(413, "Content too large", nil) unless form
    if UNSAFE_METHODS.includes?(request.method) && !csrf_valid?(form, session)
      return error_response(403, "Forbidden", nil)
    end
    check_encoding(form)
    dispatch(request, form, session.csrf_token, session.remembered)
  rescue ex : Shomen::BadInput
    error_response(400, "Bad input", ex.message)
  rescue ex : Shomen::Forbidden
    error_response(403, "Forbidden", nil)
  rescue ex : Shomen::NotFound
    error_response(404, "Not found", nil)
  rescue ex : Shomen::Conflict
    error_response(409, "Conflict", CONFLICT_DETAIL)
  rescue ex : Shomen::Unavailable
    error_response(503, "Unavailable", UNAVAILABLE_DETAIL)
  rescue ex
    Log.error(exception: ex) { "unhandled exception" }
    error_response(500, "Error", @production ? nil : ex.message)
  end

  # nil means the body is over MAX_FORM_BYTES and was not read to the end.
  private def read_form(request : HTTP::Request) : URI::Params?
    return URI::Params.new unless UNSAFE_METHODS.includes?(request.method)
    media_type = request.headers["Content-Type"]?.try(&.split(';').first.strip.downcase)
    return URI::Params.new unless media_type == FORM_TYPE
    body = request.body
    return URI::Params.new unless body
    return nil if (request.content_length || 0) > MAX_FORM_BYTES
    buffer = IO::Memory.new
    return nil if IO.copy(body, buffer, MAX_FORM_BYTES + 1) > MAX_FORM_BYTES
    URI::Params.parse(buffer.to_s)
  end

  private def check_encoding(form : URI::Params) : Nil
    form.each do |key, value|
      unless key.valid_encoding? && value.valid_encoding?
        raise Shomen::BadInput.new("invalid form encoding")
      end
    end
  end

  private def csrf_valid?(form : URI::Params, session : Shomen::Session) : Bool
    sent = form[CSRF_FIELD]?
    return false unless sent
    @sessions.csrf_valid?(session, sent)
  end

  private def error_response(status : Int32, heading : String, detail : String?) : Shomen::Response
    Shomen::Response.html(Shomen::ErrorView.new(heading, detail).to_html, status)
  end

  private def write_response(context : HTTP::Server::Context, response : Shomen::Response, session : Shomen::Session) : Nil
    context.response.status_code = response.status
    context.response.content_type = response.content_type
    response.headers.each do |entry|
      name, values = entry
      context.response.headers[name] = values
    end
    # A route may answer one URL with a document or a fragment.
    context.response.headers.add("Vary", Shomen::Route::TARGET_HEADER)
    # Behind HTTPS the cookie goes out every time, so one issued over HTTP
    # before the switch is replaced with a Secure one.
    # A cookie that only SHOMEN_SECRET_VERIFY verified goes out again under
    # SHOMEN_SECRET.
    if session.fresh? || session.reissue? || @https
      context.response.headers.add("Set-Cookie", @sessions.cookie(session, @https).to_set_cookie_header)
    end
    if response.remember > 0
      context.response.headers.add("Set-Cookie", @sessions.append_cookie(session, response.remember, @https).to_set_cookie_header)
    end
    context.response.headers["X-Content-Type-Options"] = "nosniff"
    context.response.headers["Referrer-Policy"] = "no-referrer"
    context.response.headers["X-Frame-Options"] = "DENY"
    # A route that needs more, such as images from another origin, sends its own.
    context.response.headers["Content-Security-Policy"] = CSP unless response.headers.has_key?("Content-Security-Policy")
    # While the server shuts down, no connection is kept for another request.
    context.response.headers["Connection"] = "close" if @connections.draining?
    if context.request.method == "HEAD"
      context.response.content_length = response.body.bytesize
      finish(context.response)
    elsif response.is_a?(Shomen::SSE)
      @connections.stream
      stream(context.response, response)
    else
      context.response.print(response.body)
      finish(context.response)
    end
  end

  # HTTP::Server closes and flushes a response only after call returns, when
  # the request no longer counts as busy, so a shutdown could end the
  # process first. The response is closed and flushed here instead; the
  # later close does nothing. A close with nothing left in the response's
  # buffer does not flush the connection, hence the flush.
  private def finish(output : HTTP::Server::Response) : Nil
    output.close
    output.flush
  end

  # A write fails once the client has left, and that ends the stream.
  private def stream(output : HTTP::Server::Response, sse : Shomen::SSE) : Nil
    sse.run(output)
  rescue HTTP::Server::ClientError
  end
end
