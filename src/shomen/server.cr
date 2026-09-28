require "http/server"
require "http/server/handler"
require "random/secure"
require "crypto/subtle"

class Shomen::Server
  include HTTP::Handler

  UNSAFE_METHODS = {"POST", "PUT", "PATCH", "DELETE"}
  FORM_TYPE      = "application/x-www-form-urlencoded"
  CSRF_FIELD     = "_csrf"
  MAX_FORM_BYTES = 1_048_576

  @@generated_secret : String?

  def self.start(host : String = "127.0.0.1", port : Int32 = 3000, https : Bool = false) : Nil
    Shomen::Router.entries
    server = HTTP::Server.new([new(https: https)])
    server.bind_tcp(host, port)
    server.listen
  end

  def self.secret_from_env : String
    if secret = ENV["SHOMEN_SECRET"]?.presence
      return secret
    end
    @@generated_secret ||= begin
      STDERR.puts "shomen: SHOMEN_SECRET is not set; using a random secret until restart"
      Random::Secure.hex(32)
    end
  end

  def initialize(secret : String = Shomen::Server.secret_from_env, @https : Bool = false)
    @sessions = Shomen::SessionStore.new(secret)
  end

  def call(context : HTTP::Server::Context) : Nil
    session = @sessions.load(context.request.cookies[Shomen::Session::COOKIE]?.try(&.value))
    write_response(context, respond(context.request, session), session)
  end

  def dispatch(request : HTTP::Request, form : URI::Params = URI::Params.new, csrf_token : String = "") : Shomen::Response
    handler = Shomen::Router.find(request.method, request.path)
    return error_response(404, "Not found", nil) unless handler
    handler.call(request, form, csrf_token)
  end

  private def respond(request : HTTP::Request, session : Shomen::Session) : Shomen::Response
    form = read_form(request)
    return error_response(413, "Content too large", nil) unless form
    if UNSAFE_METHODS.includes?(request.method) && !csrf_valid?(form, session)
      return error_response(403, "Forbidden", nil)
    end
    check_encoding(form)
    dispatch(request, form, session.csrf_token)
  rescue ex : Shomen::BadInput
    error_response(400, "Bad input", ex.message)
  rescue ex : Shomen::Forbidden
    error_response(403, "Forbidden", nil)
  rescue ex : Shomen::NotFound
    error_response(404, "Not found", nil)
  rescue ex
    error_response(500, "Error", ex.message)
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
    Crypto::Subtle.constant_time_compare(sent, session.csrf_token)
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
    # Behind HTTPS the cookie goes out every time, so one issued over HTTP
    # before the switch is replaced with a Secure one.
    if session.fresh? || @https
      context.response.headers.add("Set-Cookie", @sessions.cookie(session, @https).to_set_cookie_header)
    end
    context.response.headers["X-Content-Type-Options"] = "nosniff"
    context.response.headers["Referrer-Policy"] = "no-referrer"
    context.response.headers["X-Frame-Options"] = "DENY"
    if context.request.method == "HEAD"
      context.response.content_length = response.body.bytesize
    else
      context.response.print(response.body)
    end
  end
end
