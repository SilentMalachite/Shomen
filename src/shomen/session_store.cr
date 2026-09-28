require "http"
require "openssl/hmac"
require "crypto/subtle"
require "random/secure"

# Holds no server-side state: the id is signed and the csrf token is
# derived from it, so a session survives a restart with the same secret.
class Shomen::SessionStore
  def initialize(@secret : String)
  end

  def load(cookie_value : String?) : Shomen::Session
    if cookie_value && (id = verify(cookie_value))
      return Shomen::Session.new(id, false, csrf_token_for(id))
    end
    id = Random::Secure.hex(32)
    Shomen::Session.new(id, true, csrf_token_for(id))
  end

  def cookie(session : Shomen::Session, secure : Bool) : HTTP::Cookie
    HTTP::Cookie.new(
      Shomen::Session::COOKIE,
      "#{session.id}.#{sign(session.id)}",
      path: "/",
      http_only: true,
      secure: secure,
      samesite: HTTP::Cookie::SameSite::Lax,
    )
  end

  private def sign(id : String) : String
    OpenSSL::HMAC.hexdigest(:sha256, @secret, id)
  end

  # The "csrf:" prefix keeps the token distinct from the cookie signature.
  private def csrf_token_for(id : String) : String
    OpenSSL::HMAC.hexdigest(:sha256, @secret, "csrf:" + id)
  end

  private def verify(value : String) : String?
    id, dot, signature = value.rpartition('.')
    return nil if dot.empty? || id.empty?
    Crypto::Subtle.constant_time_compare(sign(id), signature) ? id : nil
  end
end
