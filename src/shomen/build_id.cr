module Shomen
  # Changes with every compile, so processes of one binary share it
  # (docs/decisions/20261001-phase7-etag.md).
  BUILD_ID = {{ run("./generate_build_id").stringify }}
end
