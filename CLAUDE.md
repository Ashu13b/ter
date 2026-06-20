# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

TER is a Termux shell environment (v1.2) for a single mobile device (OnePlus 13R, Zsh primary / Bash fallback). It is a *configuration* repo, not an application. Edits in `~/ter/` are deployed by copying files into the runtime directory `~/.shell.d/`.

## Core workflow

- **Always edit in `~/ter/`** (this repo, the source of truth). Never edit `~/.shell.d/` directly — it is overwritten on every install.
- **Deploy after every change**: `bash ~/ter/install.sh`. The installer wipes and re-copies `core/`, `network/`, `user/`, `docs/` into `~/.shell.d/`, deploys `termux.properties`, `.tmux.conf`, and `motd`, and appends a SHELL.D loader block to `~/.bashrc` if missing. `.zshrc` sources `.bashrc`.
- **Test in a new terminal** after deploying. There is no test suite — verification is interactive (open a new shell, run the command).
- **Reload current shell**: `re` (alias).
- **Shell compatibility**: every `.sh` must work under both Bash and Zsh. Use `$CURRENT_SHELL` guards where behavior diverges.

## Loader contract

`install.sh` appends a loader to `.bashrc` that, in order, sources every `*.sh` (maxdepth 1, sorted) under `~/.shell.d/core/`, then `network/`, then `user/`. File ordering inside a directory is lexical — that is why files use numeric prefixes (`00-style.sh`, `01-config.sh`, `02-tmux.sh`). Anything dropped into these directories is auto-sourced; nothing imports anything explicitly.

## App registration system

Third-party projects register under `~/.shell.d/apps/<name>/` with a `manifest.json` (name, version, description, commands) plus any `*.sh` files (auto-sourced by `core/app-loader.sh`). `apps list` enumerates them. NEXUS (`~/nexus/`) is the only consumer today; its source lives in `~/nexus/app/` and is deployed by `~/nexus/setup.sh` — **not** by this repo's installer.

## Key entry points

- `core/app-loader.sh` — scans `~/.shell.d/apps/` and defines the `apps` registry command.
- `core/theme.sh` + `core/theme_colors.sh` — prompt/theme. Theme switching is exposed via `ter theme` (see `user/ter_cmd.sh`); themes are baked into `.tmux.conf` and swapped by rewriting both `~/.tmux.conf` and `~/ter/.tmux.conf`.
- `user/aliases.sh` — base aliases plus the custom `cd()` function that special-cases `cd ws` / `cd dl`.
- `user/optimize.py` + `user/optimize.sh` — background stability engine. `user/z-run.sh` runs the compact one-line status on every interactive startup.
- `user/adb_utils.sh` + `user/adb-audit.py` + `user/adb-manage.py` + `user/adb_common.py` — ADB-over-WiFi tooling. `adb_common.py` is the shared Python helper for the two CLIs.
- `user/tab_title.sh` — `tabname` function; when inside tmux it calls `tmux rename-window` directly (not escape sequences) to avoid races.
- `network/scan.sh` (`scan net`, `scan sniff`) and `network/adb_connect.sh` (`adbcon`).
- `make_motd.py` — regenerates the `motd` banner file.

## Files outside this repo that this repo writes to

| Path | Written by |
|---|---|
| `~/.shell.d/{core,network,user,docs}/` | `install.sh` (rm -rf then cp) |
| `~/.termux/termux.properties` | `install.sh` |
| `~/.tmux.conf` | `install.sh` and `ter theme` |
| `/data/data/com.termux/files/usr/etc/motd` | `install.sh` (only if writable) |
| `~/.bashrc` | `install.sh` (appends loader once) |

## Conventions worth knowing

- No build step, no linter, no tests configured. "Correct" = sources cleanly in a fresh Bash and Zsh shell and the documented command works.
- Python utilities (`optimize.py`, `adb-*.py`, `make_motd.py`) are invoked from shell wrappers; they target the system `python3` available in Termux.
- `~/ter/.tmux.conf` and `~/.tmux.conf` must be kept in sync — `ter theme` writes both; manual edits should too.
- See `DEVELOPMENT.md` for version history and `docs/cli_manual.md` for the full user-facing command reference.
