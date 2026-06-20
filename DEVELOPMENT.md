# TER Development Handoff

This document captures the full development context for a new AI agent or developer to continue work on this project.

---

## Project Identity

- **Name**: TER (Termux Environment Repository)
- **Version**: 1.2
- **Repo**: `~/ter` → pushed to GitHub as [Ashu13b/ter](https://github.com/Ashu13b/ter)
- **Deploy target**: `~/.shell.d/` (sourced by `.bashrc` and `.zshrc`)
- **Device**: OnePlus 13R (Snapdragon 8 Gen 3, Adreno 750 GPU)
- **Shell**: Zsh (Oh My Zsh) as primary, Bash as fallback

---

## Architecture

```
~/ter/                          ← Git repository (source of truth)
├── core/                       ← Shell foundation (colors, theme, app-loader)
├── network/                    ← Network tools (scan, adbcon)
├── user/                       ← User aliases, utilities, startup hooks
│   ├── aliases.sh              ← Base aliases & custom cd() function
│   ├── optimize.py            ← Background stability engine (Python CLI)
│   ├── optimize.sh            ← Shell alias wrapper for optimize
│   ├── z-run.sh                ← Startup hook (runs compact BG check)
│   ├── tab_title.sh            ← Tab renaming utility
│   ├── adb_utils.sh            ← ADB commands (sysinfo, screengrab, audit, manage)
│   ├── adb-audit.py            ← Device security audit engine
│   └── adb-manage.py           ← App freeze/export/standby manager
├── docs/cli_manual.md          ← Full CLI reference manual
├── install.sh                  ← Deployment script
├── motd                        ← Login banner (deployed to /usr/etc/motd)
├── termux.properties           ← Custom keyboard layout
└── README.md                   ← User-facing documentation
```

### Deployment Flow
```
bash ~/ter/install.sh
  → Copies core/, network/, user/ into ~/.shell.d/
  → Copies termux.properties into ~/.termux/
  → Copies motd into /usr/etc/motd
  → Adds SHELL.D loader to .bashrc (if not present)
  → .zshrc sources .bashrc which sources everything in ~/.shell.d/
```

### App Registration System
Third-party projects (like NEXUS) register themselves under `~/.shell.d/apps/<name>/`:
- `manifest.json` — metadata (name, version, commands)
- `aliases.sh` — app-specific aliases/functions (auto-sourced)
- `complete.sh` — tab completion definitions (auto-sourced)

NEXUS is the only registered app. Its files live in `~/nexus/app/` and are deployed via `~/nexus/setup.sh` into `~/.shell.d/apps/nexus/`.

---

## Recent Changes (v1.0 → v1.1)

### Removed Aliases
These redundant aliases were cleaned up:
| Removed | Reason | Replacement |
|:---|:---|:---|
| `h` (`cd ~`) | Redundant with bare `cd` | Type `cd` |
| `ws` (`cd /storage/...`) | Redundant with `cd ws` (custom cd function) | Type `cd ws` |
| `dl` (`cd /storage/...`) | Redundant with `cd dl` (custom cd function) | Type `cd dl` |
| `c` (`clear && pwd && ls`) | Redundant with `cls` | Type `cls` |
| `pt` (`portal`) | Duplicate of `portal` | Type `portal` |
| `tnl` (`nx`) | Duplicate of `nx` | Type `nx` |
| `bridge` (`nx cld2lan`) | Duplicate of `cld2lan` | Type `cld2lan` |

### Welcome Screen Removed
- The `welcome()` function in `user/welcome.sh` is no longer called on startup.
- It still exists as a function and can be invoked manually by typing `welcome`.
- Startup now only shows: motd banner + compact `optimize status` one-liner.


### optimize Compact Mode
- `optimize status` now prints a single compact line by default.
- `optimize status -f` / `--full` shows the original verbose box.
- Help text expanded with grouped sections and examples.

### motd Updated
- Replaced `c` reference with `cls` in the login banner.
- Version bumped to v1.1.

---

## Recent Changes (v1.1 → v1.2)

### ⌨️ Touch Keyboard Customizations (`termux.properties`)
* **Soft Keyboard Lockout Resolution:** When Tmux mouse support is on (`mouse on`), clicking the screen fails to trigger the soft keyboard. Resolved by mapping the first key in the row to `DRAWER` on tap (opens side pane) and `KEYBOARD` on swipe-up (toggles soft keyboard).
* **Stable 11-key Row:** Ergonomically placed keys for mobile thumbs, with no accidental triggers for `ssh` or `exit`.

### 🪟 Tmux Status Bar & Border Optimization (`.tmux.conf`)
* **Double-Height Tab Bar:** Programmed a 2-line Tmux status bar where the active tab's background block spans across both lines.
* **Invisible Splits:** Configured `pane-border-style` and `pane-active-border-style` to `fg=default,bg=default` to render splits completely borderless.
* **Edge Stripe Removal:** Window background styles are locked to `bg=default` (transparent background) so that Tmux inherits the native Termux transparency, removing borders and thin edge stripes.
* **Ergonomics & Performance:** Enabled dynamic mouse support (mouse scroll fast overrides, tap to focus), reduced escape-time to `0` for zero latency, and established prefix `~` (tilde) for mobile-friendly input.

### 🎨 Theme Switcher CLI Engine (`ter theme`)
* **Interactive CLI Switcher:** Added `ter theme` sub-command to the Master Controller. Developers can type a letter (`c`, `f`, `g`, `h`, `i`) to swap configurations across `~/.tmux.conf` and `~/ter/.tmux.conf` instantly.
* **Active Theme Detection:** The base `ter` dashboard parses `.tmux.conf` to display the active theme in its status table.
* **5 Preserved Eye-Preserving Themes:**
  * **Theme C:** Solarized & Sage Green (Sage green text, gold highlights)
  * **Theme F:** Midnight Indigo & Soft Lavender (Lavender text, pink/purple highlights)
  * **Theme G:** Charcoal Coffee & Warm Sand (Warm sand text, orange highlights)
  * **Theme H:** Aubergine Wine & Peach Cream (Peach cream text, terracotta highlights)
  * **Theme I (Active):** Obsidian Black & Amber Gold (Muted clay/gold text, soft gold active text, and low-contrast dark gray active tab highlights)

### 🏷️ Dynamic Tab Renaming (`tab_title.sh`)
* **Direct Tmux Renaming:** If running inside Tmux, the script uses the native `tmux rename-window` command rather than background escape sequence daemons, preventing race conditions.
* **Directory Suffix (`/`):** Added a trailing slash (`/`) to the active directory names (e.g. `ter/`) to clearly designate them as folders.
* **Clean Formatting:** Omitted the shell environment prefix (`t:`/`u:`) when running inside Tmux tabs to maximize horizontal space.

---

## Sibling Projects

### NEXUS (`~/nexus/`)
- Phone-to-Cloud tunnel orchestrator.
- Registers as a TER app via `~/nexus/app/` → `~/.shell.d/apps/nexus/`.
- Key commands: `nx`, `portal`, `watch`, `cld2net`, `lcl2net`, `cld2lcl`, `cld2lan`, `fshare`.

### AI Project (`~/ai-project/`)
- Standalone local LLM assistant using Adreno 750 GPU via OpenCL.
- Uses `llama.cpp` compiled with `-DGGML_OPENCL=ON -DGGML_OPENCL_USE_ADRENO_KERNELS=ON`.
- Model: `~/qwen2.5-1.5b-instruct-q4_k_m.gguf` (Qwen 2.5 1.5B Instruct Q4_K_M).
- Performance: ~80 t/s prompt, ~20 t/s generation.
- **Not yet integrated** into TER. The `~/ai-project/README.md` contains step-by-step integration instructions (alias + welcome screen additions) for when the user is ready.

---

## Key Files Outside This Repo

| Path | Purpose |
|:---|:---|
| `~/.bashrc` | SHELL.D loader + zoxide init |
| `~/.zshrc` | Oh My Zsh config, sources .bashrc, reloads theme |
| `~/.shell.d/` | Deployed runtime shell modules (mirrors ~/ter/) |
| `~/.shell.d/apps/nexus/` | Deployed NEXUS app integration |
| `~/.termux/termux.properties` | Deployed keyboard layout |
| `/data/data/com.termux/files/usr/etc/motd` | Deployed login banner |

---

## Development Guidelines

1. **Always edit in `~/ter/`** (the git repo), never directly in `~/.shell.d/`.
2. **After editing, deploy** by running `bash ~/ter/install.sh` (copies files to `~/.shell.d/`).
3. **For NEXUS app changes**, edit in `~/nexus/app/` and run `~/nexus/setup.sh`.
4. **Both repos must stay in sync** — if you edit a deployed file directly, copy it back to the source repo before committing.
5. **Test in a new terminal** after deploying to verify startup behavior.
6. **Shell compatibility**: All scripts must work in both Bash and Zsh. Use `$CURRENT_SHELL` checks where behavior diverges.
