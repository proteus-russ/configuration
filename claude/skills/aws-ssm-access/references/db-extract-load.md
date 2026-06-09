# DB extract → transfer → load (PostgreSQL, over SSM)

Pull a **scoped slice** of a table from a remote (prod/QA) Postgres DB and load
it into a local dev DB, using `pssh` / `pscp_out` / `pscp_in`.

This recipe is derived from a real, hand-corrected workflow — an event-scoped
slice of `requeststatistic` pulled from `reviewr2-release-01` (prod) into the
`reviewr2-dev` local DB, bounded by `requesttime BETWEEN '2025-08-01' AND
'2026-03-15'`. The original was Claude-authored and had the bugs called out at
the bottom; the version below is the **corrected** canonical pattern.

## Canonical 6-step pattern

Assume `psql` connects to the local dev DB by service/db name (`reviewr2-dev`
below) and the remote box already has `psql` + DB access in scope.

```bash
#!/usr/bin/env bash
set -euo pipefail

EC2_HOST="reviewr2-release-01"     # prefer reviewr2-qa-01 when the data allows
LOCAL_DB="reviewr2-dev"
START="2025-08-01"
END="2026-03-15"

WORK=/tmp/extract-$$ ; mkdir -p "$WORK" ; cd "$WORK"

# 1. LOCAL — build the key/filter list you want to pull (optional join key).
psql -X -A -t -F, -q "$LOCAL_DB" -c "
COPY (
  SELECT DISTINCT some_key
  FROM ...
  WHERE ...
) TO STDOUT
" > list.csv
echo "$(wc -l < list.csv) keys to fetch"

# 2. Ship the list up — pscp_out takes THREE args: <host> <local> <remote>.
pscp_out "$EC2_HOST" list.csv /tmp/list.csv

# 3. REMOTE — load the list into a temp table, join, dump the slice to a
#    COMPRESSED CSV. Pipe COPY ... TO STDOUT straight through zstd (or gzip) so
#    the uncompressed CSV never lands on the remote's /tmp — for wide/large
#    slices this is the difference between fitting in /tmp and filling it.
#    Pass START/END into the remote shell as env vars so the heredoc can use them.
pssh "$EC2_HOST" "START='$START' END='$END' bash" <<'REMOTE'
set -euo pipefail
psql -X <<SQL
CREATE TEMP TABLE _wanted (some_key varchar PRIMARY KEY);
\copy _wanted FROM '/tmp/list.csv' CSV
ANALYZE _wanted;
\copy (SELECT t.* FROM target_table t JOIN _wanted w USING (some_key) WHERE t.ts_col BETWEEN '${START}' AND '${END}') TO PROGRAM 'zstd -q -o /tmp/out.csv.zst' WITH (FORMAT csv, HEADER true)
SQL
ls -lh /tmp/out.csv.zst
REMOTE

# 4. Pull the compressed CSV back — pscp_in downloads into CWD. NO redirect.
pscp_in "$EC2_HOST" /tmp/out.csv.zst       # -> ./out.csv.zst

# 5. LOCAL — decompress on the fly and load via a staging temp table so existing
#    PKs don't collide. COPY ... FROM PROGRAM keeps the uncompressed CSV off
#    local disk too.
psql -X "$LOCAL_DB" <<SQL
CREATE TEMP TABLE _staging (LIKE target_table INCLUDING ALL);
\copy _staging FROM PROGRAM 'zstd -dc out.csv.zst' WITH (FORMAT csv, HEADER true)
INSERT INTO target_table
SELECT * FROM _staging
ON CONFLICT (target_pk) DO NOTHING;
SELECT count(*) AS staged FROM _staging;
SQL

# 6. Clean up the remote temp files you created.
pssh "$EC2_HOST" 'rm -f /tmp/list.csv /tmp/out.csv.zst'
echo "Done."
```

Notes on the steps:
- **Step 1 is optional.** If you can express the whole filter as a `WHERE` on the
  target table (e.g. just a date window), skip the key-list round-trip and do the
  `\copy (SELECT ... WHERE ts BETWEEN ...) TO PROGRAM 'zstd ...'` directly in step 3.
- **Compress on the way out** (`TO PROGRAM 'zstd ...'` / `FROM PROGRAM 'zstd -dc ...'`).
  Piping `COPY` through `zstd`/`gzip` means the bulky uncompressed CSV never touches
  the remote `/tmp` (or your local CWD) — only the compressed file is written, which
  matters when remote `/tmp` is small relative to the slice. It also shrinks the SSM
  transfer. Prefer `zstd` (faster, smaller); fall back to `gzip` if `zstd` isn't on
  the box: `TO PROGRAM 'gzip > /tmp/out.csv.gz'` and `FROM PROGRAM 'gzip -dc out.csv.gz'`.
  `TO PROGRAM`/`FROM PROGRAM` run the command **server-side relative to the `\copy`
  client** (here, the remote shell for the dump and your laptop for the load), so the
  compressor must exist wherever that `psql` runs.
- **`\copy` must be a single logical line** — it is a psql meta-command and does
  not support multi-line SQL. `COPY (...) TO STDOUT` (server-side) can span lines
  but writes to the server; `\copy` runs client-side and is what you want for
  reading/writing local files.
- **Identity/sequence columns:** after loading rows with explicit PKs into local
  dev, bump the sequence if you'll insert more locally:
  `SELECT setval(pg_get_serial_sequence('target_table','id'), max(id)) FROM target_table;`
- **FK order:** load parent tables before children, or defer constraints within a
  transaction.

## Common mistakes (these were in the original script — do not repeat)

- `pscp_out` is `<host> <local> <remote>` — **not** scp-style
  `pscp_out list.csv "host:/tmp/list.csv"`.
- `pscp_in <host> <remote>` writes the file into CWD — **never** `> redirect` its
  output (`pscp_in host /tmp/out.csv > out.csv` yields an empty file).
- Don't emit spurious `\"` escaping around args or heredoc bodies
  (e.g. `pssh \"$EC2_HOST\" ...`) — quote normally.
- Use `\copy` (one line) for local files; `COPY ... TO STDOUT` only when you
  intend to capture on the client via a shell redirect.
- **Scope on the server side.** Filter with `WHERE ... BETWEEN` / key joins on
  the remote DB; never pull the entire table and trim it locally.

## Alternatives

- **Whole small table:** dump on the box (compressed), then `pscp_in`:
  ```bash
  pssh "$EC2_HOST" "pg_dump -t public.<table> --data-only --column-inserts <db> | zstd -q -o /tmp/t.sql.zst"
  pscp_in "$EC2_HOST" /tmp/t.sql.zst
  zstd -dc t.sql.zst | psql -X "$LOCAL_DB"
  ```
- **Port-forward (no temp file on the box):** tunnel to the remote DB and run
  `pg_dump`/`psql` locally against the forwarded port:
  ```bash
  pssh "$EC2_HOST" -L 5433:<rds-endpoint>:5432 -N &   # background tunnel
  pg_dump -h localhost -p 5433 -t <table> --data-only <db> | psql -X "$LOCAL_DB"
  ```

## Safety

- Treat prod (e.g. `reviewr2-release-01`) as **read-only**; prefer `reviewr2-qa-01` /
  `reviewr2-test-01` (nonprod) when the data allows.
- **Confirm with the user before writing to the local dev DB.**
- **You MUST never attempt to write to a remote DB** - it will always fail.
- Always clean up remote `/tmp` artifacts (step 6).
