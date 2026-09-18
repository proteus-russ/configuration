# DB extract → transfer → load (PostgreSQL, over SSM)

Pull **scoped slice** of table from remote (prod/QA) Postgres into local dev DB via `pssh` / `pscp_out` / `pscp_in`. Derived from real hand-corrected workflow (event-scoped `requeststatistic` slice, `reviewr2-release-01` -> `reviewr2-dev`, bounded `requesttime BETWEEN '2025-08-01' AND '2026-03-15'`). Version below = **corrected** canonical pattern.

## Canonical 6-step pattern

Assume `psql` connects to local dev DB by service/db name (`reviewr2-dev`); remote box has `psql` + DB access.

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

Step notes:
- **Step 1 optional.** Whole filter expressible as `WHERE` on target table (e.g. date window) -> skip key-list round-trip; do `\copy (SELECT ... WHERE ts BETWEEN ...) TO PROGRAM 'zstd ...'` directly in step 3.
- **Compress on way out** (`TO PROGRAM 'zstd ...'` / `FROM PROGRAM 'zstd -dc ...'`). Uncompressed CSV never touches remote `/tmp` (or local CWD) — only compressed file written; matters when remote `/tmp` small vs slice. Also shrinks SSM transfer. Prefer `zstd`; fall back `gzip`: `TO PROGRAM 'gzip > /tmp/out.csv.gz'` / `FROM PROGRAM 'gzip -dc out.csv.gz'`. `TO PROGRAM`/`FROM PROGRAM` run **relative to the `\copy` client** (remote shell for dump, laptop for load) — compressor must exist where that `psql` runs.
- **`\copy` = single logical line** — psql meta-command, no multi-line SQL. `COPY (...) TO STDOUT` (server-side) can span lines but writes to server; `\copy` runs client-side — what you want for local files.
- **Identity/sequence columns:** after loading explicit PKs, bump sequence if inserting more locally:
  `SELECT setval(pg_get_serial_sequence('target_table','id'), max(id)) FROM target_table;`
- **FK order:** parents before children, or defer constraints in transaction.

## Common mistakes (were in original script — do not repeat)

- `pscp_out` = `<host> <local> <remote>` — **not** scp-style `pscp_out list.csv "host:/tmp/list.csv"`.
- `pscp_in <host> <remote>` writes into CWD — **never** `> redirect` (`pscp_in host /tmp/out.csv > out.csv` -> empty file).
- No spurious `\"` escaping around args/heredocs (e.g. `pssh \"$EC2_HOST\" ...`) — quote normally.
- `\copy` (one line) for local files; `COPY ... TO STDOUT` only when capturing on client via shell redirect.
- **Scope server-side.** `WHERE ... BETWEEN` / key joins on remote DB; never pull whole table, trim locally.

## Alternatives

- **Whole small table:** dump on box (compressed), then `pscp_in`:
  ```bash
  pssh "$EC2_HOST" "pg_dump -t public.<table> --data-only --column-inserts <db> | zstd -q -o /tmp/t.sql.zst"
  pscp_in "$EC2_HOST" /tmp/t.sql.zst
  zstd -dc t.sql.zst | psql -X "$LOCAL_DB"
  ```
- **Port-forward (no temp file on box):** tunnel to remote DB, run `pg_dump`/`psql` locally on forwarded port:
  ```bash
  pssh "$EC2_HOST" -L 5433:<rds-endpoint>:5432 -N &   # background tunnel
  pg_dump -h localhost -p 5433 -t <table> --data-only <db> | psql -X "$LOCAL_DB"
  ```

## Safety

- Prod (e.g. `reviewr2-release-01`) = **read-only**; prefer `reviewr2-qa-01` / `reviewr2-test-01` (nonprod) when data allows.
- **Confirm with user before writing to local dev DB.**
- **You MUST never attempt to write to a remote DB** — always fails.
- Always clean up remote `/tmp` artifacts (step 6).
