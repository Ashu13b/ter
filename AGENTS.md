# Repository Guidelines

TER is a Termux shell-environment config repo (Zsh primary, Bash fallback). This repo is the source of truth; `install.sh` deploys it to the runtime at `~/.shell.d/`.

## Workflow

- Edit files here, **never** the deployed `~/.shell.d/` copy (installer wipes and re-copies it).
- Verify: `bash smoke.sh` — the only automated check. It runs `bash -n` on every `.sh`, `py_compile` on every `.py`, an isolated install/upgrade/rollback test, and sources all modules in clean Bash **and** Zsh checking that expected commands exist. Run it after any module change.
- Commit gate: `install.sh` installs a `.git/hooks/pre-commit` that runs `smoke.sh` and rejects the commit on failure. The hook is untracked — a fresh clone has no gate until `install.sh` runs.
- Deploy: `bash install.sh` (copies `core/ network/ user/ docs/` to `~/.shell.d/`, deploys `termux.properties`, `.tmux.conf`, `motd`, appends the guarded loader to both `~/.bashrc` and `~/.zshrc`). Then test in a **new terminal session**: the loader is guarded per shell PID (`TER_LOADED_PID`), so `re` re-sources the rc files but does **not** re-run the modules in the current shell.
- `ter doctor` checks repo-vs-runtime drift; `ter sync` copies runtime changes back into the repo — review the diff it produces before committing. `.terignore` controls what doctor/sync skip.
- No build step, linter, or test framework beyond `smoke.sh`.

## Loader contract (easy to get wrong)

The loader sources every `*.sh` (maxdepth 1, lexical order) in `~/.shell.d/core/`, then `network/`, then `user/`. Nothing imports anything explicitly, so:
- Numeric prefixes encode ordering (`00-style.sh`, `01-config.sh`, `user/02-tmux.sh`) — name new modules accordingly.
- Any `.sh` dropped into these dirs runs at every shell startup; keep it fast and side-effect-safe.
- Third-party apps register under `~/.shell.d/apps/<name>/` (auto-sourced, `manifest.json` metadata); NEXUS is deployed by its own repo, not this installer.

## Generated files — do not hand-edit

- `motd` — regenerate with `python3 make_motd.py` (gitignored artifact).
- `device.lock` — written by `ter snapshot`.
- `~/.tmux.conf` is a symlink to the repo's `.tmux.conf` (created by `install.sh`) — edit the repo file; `ter theme` writes through the symlink. Only when the symlink is missing does `ter theme` fall back to writing both copies, which must then be kept in sync manually.

## Conventions

- Every `.sh` must work under both Bash and Zsh; use `$CURRENT_SHELL` guards only where behavior truly differs.
- Shell module names are mixed kebab/snake (`alias-manager.sh`, `adb_utils.sh`, `ter_cmd.sh`) — keep existing filenames when modifying (the loader, wrappers, and docs reference them by name); Python names likewise (`adb-audit.py`, `adb_common.py`). Don't rename. Python targets Termux system `python3` and is invoked from shell wrappers.
- Secrets: variable names only in `secrets.template`; live values in gitignored `~/.config/ter/secrets.env` (sourced by `core/01-config.sh`). Never commit values.
- Commits: concise scoped imperative subjects, both styles in history — `ter: expand doctor checks` and `fix(tab_title): handle long options`.

## References

`CLAUDE.md` has a deeper architecture map (entry points, files written outside the repo); `docs/cli_manual.md` is the user-facing command reference; `DEVELOPMENT.md` holds version history.
