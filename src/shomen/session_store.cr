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

  # append_value is the shomen_append cookie, read only for the session the
  # first cookie names.
  def load(cookie_value : String?, append_value : String? = nil, now : Time = Time.utc) : Shomen::Session
    if cookie_value
      if id = verify(cookie_value, @secret)
        return Shomen::Session.new(id, false, csrf_token_for(@secret, id), remembered: remembered(id, append_value, now))
      end
      if (key = @verify_secret) && (id = verify(cookie_value, key))
        return Shomen::Session.new(id, false, csrf_token_for(@secret, id), reissue: true, remembered: remembered(id, append_value, now))
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

  # Makes the session remember id until Shomen::Session::REMEMBER after now.
  def append_cookie(session : Shomen::Session, id : Int64, secure : Bool, now : Time = Time.utc) : HTTP::Cookie
    expires = (now + Shomen::Session::REMEMBER).to_unix
    HTTP::Cookie.new(
      Shomen::Session::APPEND_COOKIE,
      "#{id}.#{expires}.#{sign_append(@secret, session.id, id, expires)}",
      path: "/",
      max_age: Shomen::Session::REMEMBER,
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

  # The session id in the message binds the cookie to one session.
  private def sign_append(key : String, session_id : String, id : Int64, expires : Int64) : String
    OpenSSL::HMAC.hexdigest(:sha256, key, "append:#{session_id}.#{id}.#{expires}")
  end

  # The id the append cookie holds for session_id, under either secret,
  # until it expires; 0 otherwise.
  private def remembered(session_id : String, value : String?, now : Time) : Int64
    return 0_i64 unless value
    parts = value.split('.')
    return 0_i64 unless parts.size == 3
    id = parts[0].to_i64?(whitespace: false)
    expires = parts[1].to_i64?(whitespace: false)
    return 0_i64 unless id && expires && id > 0 && now.to_unix < expires
    signed = keys.any? { |key| Crypto::Subtle.constant_time_compare(sign_append(key, session_id, id, expires), parts[2]) }
    signed ? id : 0_i64
  end

  private def verify(value : String, key : String) : String?
    id, dot, signature = value.rpartition('.')
    return nil if dot.empty? || id.empty?
    Crypto::Subtle.constant_time_compare(sign(key, id), signature) ? id : nil
  end
end
