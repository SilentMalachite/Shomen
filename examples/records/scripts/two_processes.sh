set -eu
mkdir -p bin
crystal build src/records.cr -o bin/records
crystal build scale_out/check.cr -o bin/check
RECORDS_PORT=3001 bin/records &
first=$!
RECORDS_PORT=3002 bin/records &
second=$!
trap 'kill "$first" "$second" 2>/dev/null || true' EXIT
bin/check http://127.0.0.1:3001 http://127.0.0.1:3002
kill -TERM "$first" "$second"
wait "$first"
wait "$second"
trap - EXIT
