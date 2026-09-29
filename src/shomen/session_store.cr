require "http"
require "openssl/hmac"
require "crypto/subtle"
require "random/secure"

# Holds no server-side state: the id is signed and the csrf token is
# derived from it, so a session survives a restart with the same secret.
# A second secret only verifies, so the secret can change without ending
# sessions (docs/decisions/20260929-phase6-secret-verify.md).
class Shomen::SessionStore
  def initialize(@secret : String, @verify_secret : String? = nil)
  end

  def load(cookie_value : String?) : Shomen::Session
    if cookie_value
      if id = verify(cookie_value, @secret)
        return Shomen::Session.new(id, false, csrf_token_for(@secret, id))
      end
      if (key = @verify_secret) && (id = verify(cookie_value, key))
        return Shomen::Session.new(id, false, csrf_token_for(@secret, id), reissue: true)
      end
    end
    id = Random::Secure.hex(32)
    Shomen::Session.new(id, true, csrf_token_for(@secret, id))
  end

  # True for the session's token under either secret, so a form rendered
  # before the secret changed still posts.
  def csrf_valid?(session : Shomen::Session, sent : String) : Bool
    keys.any? { |key| Crypto::Subtle.constant_time_compare(sent, csrf_token_for(key, session.id)) }
  end

  def cookie(session : Shomen::Session, secure : Bool) : HTTP::Cookie
    HTTP::Cookie.new(
      Shomen::Session::COOKIE,
      "#{session.id}.#{sign(@secret, session.id)}",
      path: "/",
      http_only: true,
      secure: secure,
      samesite: HTTP::Cookie::SameSite::Lax,
    )
  end

  private def keys : Array(String)
    if key = @verify_secret
      [@secret, key]
    else
      [@secret]
    end
  end

  private def sign(key : String, id : String) : String
    OpenSSL::HMAC.hexdigest(:sha256, key, id)
  end

  # The "csrf:" prefix keeps the token distinct from the cookie signature.
  private def csrf_token_for(key : String, id : String) : String
    OpenSSL::HMAC.hexdigest(:sha256, key, "csrf:" + id)
  end

  private def verify(value : String, key : String) : String?
    id, dot, signature = value.rpartition('.')
    return nil if dot.empty? || id.empty?
    Crypto::Subtle.constant_time_compare(sign(key, id), signature) ? id : nil
  end
end
