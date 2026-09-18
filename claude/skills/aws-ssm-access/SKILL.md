---
name: aws-ssm-access
description: >-
  EC2 access over AWS Systems Manager (SSM) via the Proteus/VentureTech
  `aws-utils` tools (`pssh`, `pscp_in`, `pscp_out`). Use for any ssh,
  remote command, file copy, or port-forward involving an EC2 instance,
  including pulling production/QA data into a local or dev database.
  Also triggers on the literal names `pssh`/`pscp_in`/`pscp_out`,
  "session manager", "ssh over ssm", or "LEAPP". Machine-wide
  conventions, not repo-specific.
disable-model-invocation: true
---

# AWS SSM access (aws-utils)

EC2 instances: **no public SSH, no bastion**. All access = SSH-over-SSM: `ssh`/`scp` tunnel through `aws ssm start-session` (document `AWS-StartSSHSession`). `aws-utils` wrappers handle LEAPP creds, Name-tag→instance-id resolution, SSM ProxyCommand.

Source repo: <https://github.com/VentureTech/aws-utils>

## Prerequisites

- `pssh`, `pscp_in`, `pscp_out`, `start-leapp-session`, `add-leapp-session` always on `$PATH` — bare names. **Never** source anything or reference `$PSYS_AWS_UTILS_HOME` in generated scripts.
- **Run tools through interactive zsh** — env (`PSYS_AWS_UTILS_HOME`, etc.) set in interactive rc files. Plain non-interactive `Bash` fails: `ERROR: aws-utils is not configured (no PSYS_AWS_UTILS_HOME)`. Wrap every call:

  ```bash
  zsh -ic "pssh reviewr2-qa-01 \"hostname\""
  # heredoc form: pipe the remote script into pssh's stdin
  zsh -ic "pssh reviewr2-qa-01 bash" <<'REMOTE'
  psql -X -At -c "select now()"
  REMOTE
  ```
- `leapp`, `aws`, `session-manager-plugin` installed.
- LEAPP sessions auto-start: each tool runs `aws sts get-caller-identity`, calls `leapp session start <profile>` if creds stale. No manual step.

## The three commands

```
pssh     <host> [remote-cmd / ssh-args...]
pscp_in  <host> <remote-path>            # downloads into CWD
pscp_out <host> <local-path> <remote-path>
```

`<host>` = EC2 **Name tag** (e.g. `reviewr2-qa-01`), not instance-id.

### `pssh` — ssh / remote command / port-forward
Everything after `<host>` passes straight to `ssh`:
```bash
pssh reviewr2-qa-01                          # interactive shell
pssh reviewr2-qa-01 "hostname && whoami"     # one-off remote command
pssh reviewr2-qa-01 -L 5433:my-rds:5432      # local port-forward
pssh reviewr2-qa-01 bash <<'REMOTE'          # run a heredoc script remotely
set -euo pipefail
psql -X -c "select now()"
REMOTE
```

### `pscp_in` — copy FROM remote into CWD
```bash
pscp_in reviewr2-qa-01 /tmp/out.csv          # lands ./out.csv in CWD
```
Downloads into CWD. **Do NOT redirect stdout** — `pscp_in host /tmp/x.csv > x.csv` wrong (empty file). No `host:path` form.

### `pscp_out` — copy local TO remote (THREE separate args)
```bash
pscp_out reviewr2-qa-01 ./list.csv /tmp/list.csv
```
**Host = own argument.** NOT scp-style — never `pscp_out ./list.csv "host:/tmp/list.csv"`.

### Reconstructing ad-hoc ssh/scp
Raw `ssh`/`scp` (e.g. rsync) — wrappers use:
```bash
ProxyCommand="sh -c \"aws --profile <profile> ssm start-session --target %h \
  --document-name AWS-StartSSHSession --parameters 'portNumber=%p'\""
ssh -S none -o "ProxyCommand=$ProxyCommand" -oStrictHostKeyChecking=no <instance-id> ...
```
`<instance-id>` from
`aws ec2 describe-instances --filters "Name=tag:Name,Values=<name-with -→*-*>" \
  --query 'Reservations[*].Instances[*].InstanceId' --output text`.

## Instance & profile resolution

Host arg -> LEAPP profile two ways:
1. **Exact match** in `ec2hosts` map (`~/.aws-utils-user.inc.zsh`).
2. Else **pattern** `NAME-CONTEXT-NN`:
   - `release` → `<name>-server-prod`
   - `fo` → `<name>-server-fo`
   - else → `<name>-server-nonprod`

| Host                  | Environment | LEAPP profile            |
|-----------------------|-------------|--------------------------|
| `reviewr2-release-01` | **PROD**    | `reviewr-server-prod`    |
| `reviewr2-qa-01`      | QA/nonprod  | `reviewr-server-nonprod` |
| `reviewr2-test-01`    | test/nonprod| `reviewr-server-nonprod` |
| `engage-release-01`   | **PROD**    | `engage-server-prod`     |
| `engage-qa-01`        | QA/nonprod  | `engage-server-nonprod`  |
| `engage-test-01`      | test/nonprod| `engage-server-nonprod`  |

## Conventions & gotchas

- `-S none`: no shared control socket — SSM tunnel not persistent between invocations (intentional; port-forwards over reused conn misbehave).
- `-oStrictHostKeyChecking=no`: SSM transport -> MITM negligible; no known_hosts churn.
- Stopped instance auto-started + hardcoded `sleep 20` for SSM agent -> one-time ~25s delay on cold instance.
- Name tags may contain whitespace; tools wildcard `-`→`*-*` internally. Use dashed alias (`reviewr2-qa-01`), not raw tag.

## Pulling partial DB data from prod/QA into local dev

Headline use case (extract date-/key-scoped slice on remote DB, transfer CSV, load locally). **Before extracting anything from production, satisfy PII/PHI gate in _Safety rules_ — for Engage, pull from sanitized snapshot, not prod.** Full corrected PostgreSQL recipe — staging-table load, `\copy` rules, common mistakes — in **[references/db-extract-load.md](references/db-extract-load.md)**. Read it before writing such a script.

Users/auth queries in any Proteus Framework DB (who is principal, groups/roles, usernames): use **`pf-users-schema`** skill first — no `principal` table (principals live in `role` with `type='principal'`); usernames on `credentials.role_fk`, not `credentials.userid`.

## Safety rules

- **PII/PHI gate — you MUST prompt before any production data leaves prod.**
  Before extracting, downloading, or copying **any** data off a production
  instance or DB, stop and ask the user to explicitly confirm the data
  contains no PII or PHI that is meant to be scrubbed before leaving
  production. Get that confirmation **every time** — never proceed on
  assumption. Applies to every product, not just the examples below.
  - **Engage:** use the **sanitized database snapshots** instead of production.
    Engage production data is off-limits for extraction — do **not** pull it,
    ever; the user is not allowed to override. Engage flags PHI-protected
    records via the `phisafeguards` column in `app.company`; that safeguard is
    why this data must not leave prod unscrubbed.
- Treat **prod (`reviewr2-release-01`) as read-only**. Prefer QA/nonprod (`reviewr2-qa-01` / `reviewr2-test-01`) when data allows.
- Always **scope extract server-side** (`WHERE ... BETWEEN`, `LIMIT`, key joins) — never pull whole table, filter locally.
- **Confirm before writing to local dev DB.**
- **You MUST never attempt to write to a remote DB** — always fails.
- Clean up remote `/tmp` files you create.
