# Run by build_id.cr while the application compiles; nothing requires it.
require "random/secure"

print Random::Secure.hex(16)
