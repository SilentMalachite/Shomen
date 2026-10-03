# 05 Scale out

> Canonical text. Japanese translation: [../05-SCALE-OUT.md](../05-SCALE-OUT.md).

These steps take [`examples/records`](../../examples/records) from one process on SQLite to two processes on one Postgres database, first without a replica and then with one. Only environment variables change. The source stays the same. Run every command from `examples/records`.

## Environment variables

| Variable | Default | Meaning |
|---|---|---|
| `RECORDS_DATABASE_URL` | `sqlite3://./var/records.sqlite3` | The primary database, `sqlite3://…` or `postgres://…` |
| `RECORDS_REPLICA_URL` | none | A Postgres replica for reads. Unset or empty means no replica |
| `RECORDS_PORT` | `3000` | The port on 127.0.0.1, from 1 to 65535 |
| `SHOMEN_SECRET` | a random secret until restart | Signs the session cookie and the CSRF token. Every process needs the same value |
| `SHOMEN_ENV` | none | `production` requires a `SHOMEN_SECRET` of at least 32 bytes and hides exception messages |

## One process on SQLite

```sh
shards install
mkdir -p var
crystal run src/records.cr
```

Open <http://127.0.0.1:3000/items>. Ctrl-C stops it: the server finishes the requests in progress, then the ledger stops and the store closes.

## Two processes on Postgres

You need a Postgres server (CI uses Postgres 17) and an existing database whose user may create tables. Both processes use the same database and the same secret:

```sh
export RECORDS_DATABASE_URL=postgres://localhost/records
export SHOMEN_ENV=production
export SHOMEN_SECRET="$(openssl rand -hex 32)"
```

Then run these commands. CI runs them as they are, from [`scripts/two_processes.sh`](../../examples/records/scripts/two_processes.sh):

```sh
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
```

They build the application and the check, and start two processes on ports 3001 and 3002. `bin/check` waits until both answer `GET /items`. It opens the item stream of the second process, registers an item through the first, and checks that the second shows it: on the item page and the list, with the session cookies the first set, and on the open stream. Then both processes get SIGTERM, finish, and exit with status 0. A failure stops the commands with a nonzero status.

Each process runs the ledger consumer. A batch commits its rows and the checkpoint together, so each event is applied once, by whichever process reaches it first. An append in either process notifies the other, and its streams wake. The session cookie carries the id of the session's last append, so a page served by the other process waits until the ledger has reached it.

In production, put a load balancer in front of the processes and give them all the same `SHOMEN_SECRET`. To change the secret, see `SHOMEN_SECRET_VERIFY` in [00-INSTRUCTION.md](00-INSTRUCTION.md).

## With a replica

Point `RECORDS_REPLICA_URL` at one hot standby of the primary, and run the same commands:

```sh
export RECORDS_REPLICA_URL=postgres://replica.example/records
```

Pages and streams read the replica once it has reached the session's last append, and the primary when it has not within 2 seconds. Appends, consumer batches, and notifications stay on the primary. Shomen creates nothing on the replica: the ledger's tables reach it by replication. The URL must name one standby, not a pool that spreads connections over several.

CI sets `RECORDS_REPLICA_URL` to the primary's own URL. That shows the processes start and serve with a replica URL and no change to the source. A replica that lags is checked by the phase 7 specs ([decision](../decisions/20261001-phase7-replica-spec.md)).
