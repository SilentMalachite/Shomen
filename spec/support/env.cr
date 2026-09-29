# A secret long enough for SHOMEN_ENV=production.
LONG_SECRET = "0123456789abcdef0123456789abcdef"

# Sets the variables for the block, removing those whose value is nil,
# and restores them afterwards.
def with_env(values : Hash(String, _), &) : Nil
  saved = {} of String => String?
  values.each_key { |name| saved[name] = ENV[name]? }
  apply_env(values)
  begin
    yield
  ensure
    apply_env(saved)
  end
end

private def apply_env(values : Hash(String, _)) : Nil
  values.each do |name, value|
    if value
      ENV[name] = value
    else
      ENV.delete(name)
    end
  end
end
