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
---

# AWS SSM access (aws-utils)

These EC2 instances have **no public SSH and no bastion**. All access is
SSH-over-SSM: `ssh`/`scp` tunnel through `aws ssm start-session` (document
`AWS-StartSSHSession`). The `aws-utils` wrapper tools handle credential
(LEAPP) startup, Name-tag→instance-id resolution, and the SSM ProxyCommand.

Source repo: <https://github.com/VentureTech/aws-utils>

## Prerequisites

- `pssh`, `pscp_in`, `pscp_out`, `start-leapp-session`, `add-leapp-session`
  are **always on `$PATH`** — call them by bare name. **Never** source anything
  or reference `$PSYS_AWS_UTILS_HOME` in a script you generate.
- `leapp`, `aws`, and `session-manager-plugin` are installed.
- LEAPP sessions auto-start: each tool runs `aws sts get-caller-identity` and
  calls `leapp session start <profile>` if creds are stale. No manual step needed.

## The three commands

```
pssh     <host> [remote-cmd / ssh-args...]
pscp_in  <host> <remote-path>            # downloads into CWD
pscp_out <host> <local-path> <remote-path>
```

`<host>` is the EC2 **Name tag** (e.g. `reviewr2-qa-01`), not an instance-id.

### `pssh` — ssh / run remote command / port-forward
Everything after `<host>` is passed straight to `ssh`. So you can:
```bash
pssh reviewr2-qa-01                          # interactive shell
pssh reviewr2-qa-01 "hostname && whoami"     # one-off remote command
pssh reviewr2-qa-01 -L 5433:my-rds:5432      # local port-forward
pssh reviewr2-qa-01 bash <<'REMOTE'          # run a heredoc script remotely
set -euo pipefail
psql -X -c "select now()"
REMOTE
```

### `pscp_in` — copy FROM remote into current directory
```bash
pscp_in reviewr2-qa-01 /tmp/out.csv          # lands ./out.csv in CWD
```
**It downloads the file into CWD. Do NOT redirect its stdout** — `pscp_in host
/tmp/x.csv > x.csv` is wrong (produces an empty file). There is no `host:path`
form.

### `pscp_out` — copy local file TO remote (THREE separate args)
```bash
pscp_out reviewr2-qa-01 ./list.csv /tmp/list.csv
```
**The host is its own argument.** It is NOT scp-style — do not write
`pscp_out ./list.csv "host:/tmp/list.csv"`.

### Reconstructing ad-hoc ssh/scp
If you ever need raw `ssh`/`scp` (e.g. rsync), the wrappers use:
```bash
ProxyCommand="sh -c \"aws --profile <profile> ssm start-session --target %h \
  --document-name AWS-StartSSHSession --parameters 'portNumber=%p'\""
ssh -S none -o "ProxyCommand=$ProxyCommand" -oStrictHostKeyChecking=no <instance-id> ...
```
where `<instance-id>` comes from
`aws ec2 describe-instances --filters "Name=tag:Name,Values=<name-with -→*-*>" \
  --query 'Reservations[*].Instances[*].InstanceId' --output text`.

## Instance & profile resolution

The host arg is resolved to a LEAPP profile two ways:
1. **Exact match** in the `ec2hosts` map (`~/.aws-utils-user.inc.zsh`).
2. Else **pattern** `NAME-CONTEXT-NN`:
   - `release` → `<name>-server-prod`
   - `fo` → `<name>-server-fo`
   - anything else → `<name>-server-nonprod`

Host examples:

| Host                  | Environment | LEAPP profile            |
|-----------------------|-------------|--------------------------|
| `reviewr2-release-01` | **PROD**    | `reviewr-server-prod`    |
| `reviewr2-qa-01`      | QA/nonprod  | `reviewr-server-nonprod` |
| `reviewr2-test-01`    | test/nonprod| `reviewr-server-nonprod` |
| `engage-release-01`   | **PROD**    | `engage-server-prod`     |
| `engage-qa-01`        | QA/nonprod  | `engage-server-nonprod`  |
| `engage-test-01`      | test/nonprod| `engage-server-nonprod`  |

## Conventions & gotchas

- `-S none`: no shared control socket — the SSM tunnel does not persist between
  invocations (intentional, since port-forwards over a reused connection misbehave).
- `-oStrictHostKeyChecking=no`: SSM transport makes MITM negligible; no
  known_hosts churn.
- A **stopped** instance is auto-started, followed by a hardcoded `sleep 20` for
  the SSM agent — expect a one-time ~25s delay on a cold instance.
- Name tags may contain whitespace, so the tools wildcard `-`→`*-*` internally.
  Use the dashed alias (`reviewr2-qa-01`), not the raw tag.

## Pulling partial DB data from prod/QA into local dev

This is the headline use case (extract a date-/key-scoped slice on the remote
DB, transfer the CSV, load it locally). **Before you extract anything from
production, satisfy the PII/PHI gate in _Safety rules_ below — for Engage that
means pulling from a sanitized snapshot, not prod.** The full corrected, worked PostgreSQL
recipe — staging-table load, `\copy` rules, and the common mistakes to avoid —
is in **[references/db-extract-load.md](references/db-extract-load.md)**. Read it
before writing such a script.

## Safety rules

- **PII/PHI gate — you MUST prompt before any production data leaves prod.**
  Before extracting, downloading, or copying **any** data off a production
  instance or DB, stop and ask the user to explicitly confirm the data
  contains no PII or PHI that is meant to be scrubbed before leaving
  production. Get that confirmation **every time** — never proceed on
  assumption. This applies to every product, not just the examples below.
  - **Engage:** use the **sanitized database snapshots** instead of production. Treat
    Engage production data as off-limits for extraction — do **not** pull it
    ever the user is not allowed to override. Engage flags PHI-protected records
    via the `phisafeguards` column in `app.company`; that safeguard is the
    reason this data must not leave prod unscrubbed.
- Treat **prod (`reviewr2-release-01`) as read-only**. Prefer QA/nonprod
  (`reviewr2-qa-01` / `reviewr2-test-01`) whenever the data allows.
- Always **scope the extract on the server side** (`WHERE ... BETWEEN`,
  `LIMIT`, key joins) — never pull a whole table and filter locally.
- **Confirm before writing to the local dev DB**
- **You MUST never attempt to write to a remote DB** - it will always fail.
- Clean up remote `/tmp` files you create.
