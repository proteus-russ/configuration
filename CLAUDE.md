# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository purpose

Personal dotfile and shell-configuration repository. Files live here in canonical form (without leading dots, sometimes with version suffixes) and are synced to/from `$HOME` using the two top-level scripts.

## Sync commands

- `./copy-to-home` — install this repo's files into `$HOME` (interactive confirm).
- `./copy-from-home` — pull current `$HOME` versions back into this repo (interactive confirm).
- `./sync-home to-home` / `./sync-home from-home` — the underlying script. `copy-to-home` and `copy-from-home` are symlinks to it; direction is inferred from `$0`.

All three invocations share [lib/sync.sh](lib/sync.sh), which contains the copy loop, parent-dir creation, failure tracking, and the final `N copied [, M failed]` summary. 
A non-zero exit means at least one file failed to copy.

The script reads three manifest files to decide what to sync. **Editing a file here is not enough — it also has to be listed in the corresponding manifest, or the sync scripts will skip it.** 
Blank lines and `#`-prefixed comments in manifests are ignored.

| Manifest | Source dir | Destination | Format |
| --- | --- | --- | --- |
| [dotfiles/files](dotfiles/files) | `dotfiles/` | `$HOME/` | two columns: `<repo-name> <home-path>` (e.g. `zshrc .zshrc`, `psqlrc-13 .psqlrc`) |
| [scripts/files](scripts/files) | `scripts/` | `$HOME/.local/bin/` | one filename per line |
| [functions/files](functions/files) | `functions/` | `$HOME/.local/functions/` | one filename per line |


## Directory roles

- `dotfiles/` — shell rc files (`zshrc`, `zprofile`, `aliasrc`), `gitconfig`, `ssh/config`, several versioned `psqlrc-*` files (only one is symlinked via `dotfiles/files` as `.psqlrc`).
- `scripts/` — executable helpers installed to `~/.local/bin/`.
- `functions/` — zsh autoload functions installed to `~/.local/functions/` (sourced by `zshrc`).
- `iterm/` — iTerm2 ZModem coprocess scripts plus setup docs ([iterm/README.md](iterm/README.md)). These are **not** installed by `copy-to-home`; they are copied manually into `/usr/local/bin` per the README.
- `postgresql/` — reference copies of `pg_hba.conf` / `postgresql.conf` for the local Postgres server. Not auto-installed; edit the live files under the Postgres data directory and mirror changes here.

## Conventions when adding files

- Adding a new dotfile: drop it in `dotfiles/`, then append a `<repo-name> <home-path>` line to `dotfiles/files`. The repo name has no leading dot; the home path does.
- Versioned configs (like the `psqlrc-*` series) are kept side-by-side so the active one can be swapped by editing the mapping in `dotfiles/files` rather than renaming files.
- New scripts must be `chmod +x` and listed in `scripts/files`; same pattern for `functions/files`.
