# Changelog

All notable changes to TER are documented here. Older history lives in
`DEVELOPMENT.md` for context (recent v1.0→v1.1→v1.2 walkthrough).

## [Unreleased]

### Added
- `ter theme next` / `rotate` — cycles through palettes with wrap-around;
  menu gains `[R]` and five new themes: Nord Frost (j), Ocean Deep (k),
  Rose Quartz (l), Matrix Emerald (m), Sunset Ember (n). Theme definitions
  consolidated into a single registry used by CLI, menu, and rotation.
- Startup self-check: a one-line warning prints when core commands
  (`ter`/`apps`) are missing after module load.
- Version-controlled pre-commit hook (`hooks/pre-commit`); installer copies
  it into `.git/hooks/`.

### Changed
- `install.sh` upgrades stale-but-guarded loader blocks in rc files
  (old word-splitting bodies) to the current null-delimited loader; bare
  marker comments elsewhere in rc files are preserved.
- `smoke.sh` syntax-checks `extras/*.sh`.
- `make_motd.py` derives paths from its own location and uses `shutil.copy`.

### Docs
- Refreshed `AGENTS.md`, `CLAUDE.md`, `.context.md`, `DEVELOPMENT.md`;
  added roadmap to `DEVELOPMENT.md`.

## [1.4] — 2026-07-03

### Changed
- Rename `devopts` → `dvop` (shorter, matches muscle memory).
- `dvop off` now confirms before flipping — the toggle also kills the
  Wireless Debugging daemon, so the message spells out the phone-side
  recovery ladder. Skip prompt with `dvop off -y`.
- `adbcon` prints the recovery ladder (previously-paired vs fresh-pair)
  when the loopback channel is dead.
- `ter info` now shows ADB connection state and current `dvop` value so
  lockout risk is visible before you flip.
- `adbcon` gained three detectable-precondition checks driven by the
  dvop-experiments findings:
  - Separates `wlan*` (STA / client link) from `ap*`/`swlan*` (hotspot).
    If only AP is up, aborts early with the "join a real Wi-Fi network"
    hint instead of wasting a 15s scan against the fallback IP.
  - Warns when the user-supplied phone IP is outside our `/24`
    (guest-network client isolation, VLAN split, wrong SSID).
  - Treats `unauthorized` device state as a revoked pairing — skips
    remaining port probes and retry loop, bounces straight to
    fresh-pair mode.

### Docs
- `docs/dvop-experiment-findings.md` — full write-up of the
  `feature/dvop-experiments` investigation, now merged to main:
  why self-granting `WRITE_SECURE_SETTINGS` is blocked on OxygenOS 15
  (three walls), why post-reboot recovery needs a real Wi-Fi STA (the
  phone's own hotspot can't rescue itself — single-radio constraint),
  and why "fake Wi-Fi" workarounds (VPN, USB-tether, Wi-Fi Direct) all
  miss the `TRANSPORT_WIFI` gate in `AdbDebuggingManager`.
  Conclusion: keep `dvop` as-is; the 7-tap dance stays the only
  unrooted escape from a self-inflicted lockout.

## [1.3] — 2026-06-22

### Added
- `ter wizard` — interactive first-run setup: storage permission, git
  identity, SSH key generation, `gh auth login`, secrets scaffold.
- `secrets.template` — curated list of expected env-var names. `ter wizard`
  copies it to `~/.config/ter/secrets.env` (gitignored); `core/01-config.sh`
  auto-sources that file each shell.
- `ter doctor` now warns when secrets named in the template are unset in
  the environment.
- `extras/install-claude.sh` — installs Claude Code CLI via npm.
- `extras/install-gcloud.sh` — provisions Google Cloud CLI inside a
  proot-distro Debian rootfs and writes a thin `gcloud` wrapper on the
  Termux side.
- `devopts on|off|toggle|status` — flip Android Developer Options via ADB
  without a phone reboot. Hides `development_settings_enabled` from
  Play-Integrity / GPS-spoof / banking-app checks.

### Fixed
- `install.sh` creates `~/.bashrc` / `~/.zshrc` if missing so the loader is
  installed on a truly fresh Termux (previously skipped when rc absent).
- `install.sh` strips inline `#` comments from `packages.txt` before
  `pkg install` (was passing comment text as package names).

## [1.2] — 2026-06-22

### Added
- `ter doctor` — drift detector comparing `~/ter` vs `~/.shell.d`.
- `ter sync` — copy drifted runtime files back into the repo.
- `ter update` — `git pull --ff-only` followed by `install.sh`.
- `ter snapshot` — diagnostic dump (uname, termux-info, pkgs, storage perm)
  to `device.lock` (gitignored).
- `ter info` — one-screen "where am I" status.
- `ter theme` — interactive CLI switcher across five eye-preserving themes
  (Solarized, Midnight, Charcoal, Aubergine, Obsidian).
- `bootstrap.sh` — curl-bash entry point for a fresh Termux: installs git,
  clones the repo, runs `install.sh` and `smoke.sh`.
- `packages.txt` — curated minimum package list; `install.sh` runs
  `pkg install -y` against it on every deploy.
- `smoke.sh` — sources every module in bash + zsh and verifies key commands
  (`re cls scan adbcon optimize tabname apps ter`). Auto-wired as the
  pre-commit hook.
- Tab title pipeline encoding `cmd / where / folder #PID`, with environment
  detection (termux vs ssh:host) and a PID suffix for agent sessions
  (`claude`, `agy`, `ai`, `aichat`, `aider`).
- Double-height tmux status bar; amber-on-black active tab for high contrast.

### Changed
- `install.sh`: `apps/` directory is never wiped during redeploy; loader is
  installed into both `.bashrc` and `.zshrc` with a `TER_LOADED` re-entry
  guard; old unguarded loader blocks are upgraded in place.
- `~/.tmux.conf` is now a symlink to the repo copy so themes only need
  to be written in one place.
- `motd` is regenerated by `install.sh` (no longer tracked in git).
- `_ter_apply_theme` writes atomically (tempfile + mv) and escapes sed
  replacement metachars so `&` in theme names no longer corrupts the conf.
- Termux extra-keys: first key tap = DRAWER (side pane), swipe-up = KEYBOARD.
- Startup banner is guarded against re-source duplication.
- Tmux `allow-rename off` + `automatic-rename off` so external apps (e.g.
  Claude Code) cannot overwrite the title set by `tab_title.sh`.

### Removed
- Unused `welcome.hook` contract from app registry docs.

## [1.1] — earlier in 2026

See `DEVELOPMENT.md` for the v1.0 → v1.1 walkthrough (alias cleanup,
welcome-screen retirement, `optimize` compact mode).

## [1.0] — initial release
- Modular shell loader (`~/.shell.d/`), app registration system, `scan`,
  `adbcon`, `optimize`, custom keyboard layout, tmux-first workflow.
