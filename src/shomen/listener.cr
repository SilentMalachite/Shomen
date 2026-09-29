require "http/server"
require "./connections"

# An HTTP::Server that tells Connections which fiber serves which
# connection, so a shutdown can close the idle ones
# (docs/decisions/20260929-phase6-shutdown.md).
class Shomen::Listener < HTTP::Server
  def initialize(@connections : Shomen::Connections, handler : HTTP::Handler)
    super(handler)
  end

  protected def dispatch(io)
    connections = @connections
    spawn do
      connections.open(io)
      handle_client(io)
    ensure
      connections.leave
    end
  end
end
