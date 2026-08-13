# Repository Guidelines

## Project Structure & Module Organization

TER is a portable Termux shell environment. Edit source files in this repository, never the deployed `~/.shell.d/` copy.

- `core/` contains shared configuration, themes, the app loader, and alias management.
- `network/` provides network and wireless-ADB helpers.
- `user/` holds user-facing shell functions plus Python ADB utilities.
- `docs/` contains the CLI reference and development notes; `extras/` contains optional installers.
- Root files include `install.sh` (deployment), `smoke.sh` (compatibility checks), `termux.properties`, `motd`, and `manifest.json`.

Keep sourced shell modules in the appropriate `core/`, `network/`, or `user/` directory; the installer deploys these directories to `~/.shell.d/`.

## Build, Test, and Development Commands

- `bash install.sh` deploys shell modules, Termux keyboard settings, and the MOTD to the local Termux environment.
- `bash smoke.sh` sources all shell modules in clean Bash and Zsh sessions and verifies expected commands exist.
- `ter doctor` (after deployment) checks repository-versus-runtime drift and configuration health.
- `ter sync` copies intentional runtime changes back into the repository; review the resulting diff before committing.

After shell changes, run the smoke test, deploy, then open a new terminal to confirm startup behavior.

## Coding Style & Naming Conventions

Write POSIX-leaning shell compatible with both Bash and Zsh; use `CURRENT_SHELL` checks only where behavior truly differs. Use four-space indentation in shell and Python, quote expansions, and keep functions small and action-oriented. Name shell modules descriptively with lowercase kebab-case (for example, `adb-utils.sh`); preserve existing filenames when modifying deployed modules. Use lowercase Python filenames with underscores, such as `adb_audit.py`.

Avoid embedding credentials or device-specific secrets. Add required variable names to `secrets.template`; live values belong in the gitignored `~/.config/ter/secrets.env`.

## Testing Guidelines

`smoke.sh` is the required regression check for module changes. Test new or changed commands in both available shells and include failures in the fix cycle. For ADB or network features, avoid destructive device actions during routine checks and document any required device state.

## Commit & Pull Request Guidelines

Recent commits use concise, scoped, imperative subjects: `ter: expand doctor checks`, `adb: rename device settings opener`, `docs: update CLI findings`. Follow `<scope>: <summary>` and keep each commit focused. Pull requests should state the user-visible change, tests run (for example, `bash smoke.sh`), deployment or device prerequisites, and screenshots only for visual Termux/tmux changes. Link related issues when applicable.
