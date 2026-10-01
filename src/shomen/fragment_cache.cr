require "./fragment"

# A fragment rendered before; Shomen::FragmentCache hands it out.
class Shomen::CachedFragment < Shomen::Fragment
  def initialize(@markup : String)
  end

  def content : Nil
    raw @markup
  end

  def to_html : String
    @markup
  end
end

# Rendered fragments that every session in the process shares, up to
# max_bytes of keys and HTML, dropping the one used least recently first.
# Nothing is invalidated by hand: the key holds what the fragment depends
# on (docs/decisions/20261001-phase7-fragment-cache.md).
class Shomen::FragmentCache
  MAX_BYTES = 16 * 1024 * 1024

  # In the order of use, least recent first.
  @entries = {} of String => String
  @bytes = 0_i64
  @lock = Mutex.new

  def initialize(@max_bytes : Int32 = MAX_BYTES)
    raise ArgumentError.new("max_bytes must be positive") unless @max_bytes > 0
  end

  # The fragment kept for key, or the one the block renders. A fragment
  # that contains csrf_token raises and is not kept. The block runs
  # outside the lock.
  def fetch(key : String, csrf_token : String, & : -> Shomen::Fragment) : Shomen::Fragment
    if markup = @lock.synchronize { use(key) }
      return Shomen::CachedFragment.new(markup)
    end
    markup = yield.to_html
    if !csrf_token.empty? && markup.includes?(csrf_token)
      raise ArgumentError.new("fragment #{key} contains the CSRF token, and every session shares a cached fragment")
    end
    @lock.synchronize { keep(key, markup) }
    Shomen::CachedFragment.new(markup)
  end

  private def use(key : String) : String?
    markup = @entries.delete(key)
    @entries[key] = markup if markup
    markup
  end

  private def keep(key : String, markup : String) : Nil
    if old = @entries.delete(key)
      @bytes -= key.bytesize + old.bytesize
    end
    size = key.bytesize.to_i64 + markup.bytesize
    return if size > @max_bytes
    while @bytes + size > @max_bytes
      dropped, dropped_markup = @entries.shift
      @bytes -= dropped.bytesize + dropped_markup.bytesize
    end
    @entries[key] = markup
    @bytes += size
  end
end
