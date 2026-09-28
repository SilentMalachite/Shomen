require "http/server"
require "http/server/handler"

class Shomen::Server
  include HTTP::Handler

  def self.start(host : String = "127.0.0.1", port : Int32 = 3000) : Nil
    Shomen::Router.entries
    server = HTTP::Server.new([new])
    server.bind_tcp(host, port)
    server.listen
  end

  def call(context : HTTP::Server::Context) : Nil
    write_response(context, dispatch(context.request))
  rescue ex : Shomen::BadInput
    write_response(context, error_response(400, "Bad input", ex.message))
  rescue ex : Shomen::NotFound
    write_response(context, error_response(404, "Not found", nil))
  rescue ex
    write_response(context, error_response(500, "Error", ex.message))
  end

  def dispatch(request : HTTP::Request) : Shomen::Response
    handler = Shomen::Router.find(request.method, request.path)
    return error_response(404, "Not found", nil) unless handler
    handler.call(request)
  end

  private def error_response(status : Int32, heading : String, detail : String?) : Shomen::Response
    Shomen::Response.html(Shomen::ErrorView.new(heading, detail).to_html, status)
  end

  private def write_response(context : HTTP::Server::Context, response : Shomen::Response) : Nil
    context.response.status_code = response.status
    context.response.content_type = response.content_type
    response.headers.each do |entry|
      name, value = entry
      case value
      when String
        context.response.headers[name] = value
      when Array
        context.response.headers[name] = value.join(", ")
      end
    end
    context.response.headers["X-Content-Type-Options"] = "nosniff"
    context.response.headers["Referrer-Policy"] = "no-referrer"
    context.response.headers["X-Frame-Options"] = "DENY"
    context.response.print(response.body)
  end
end
