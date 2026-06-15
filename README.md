# 🌟 TER: Termux Custom Environment (v1.1)

TER is a portable, independent Termux environment configuration repository. It installs a modular shell structure, custom keyboard layout, and a modular app-registration system. It works completely standalone or can be integrated with other projects (like NEXUS) via the registry system.

> [!TIP]
> For a detailed guide on all custom CLI utilities, usage flags, and offline capabilities, see the [CLI Manual](docs/cli_manual.md).

---

## 📂 Directory Structure (`~/.shell.d/`)
All modular scripts are automatically sourced on terminal startup. They are organized into directories:

### 📂 `core/` (System Foundation)
* **`00-style.sh`**: Defines global terminal colors (`$C_CYAN`, `$C_RED`, etc.) and the `style_header` function.
* **`01-config.sh`**: Core environment settings.
* **`alias-manager.sh`**: Utility for adding/managing custom aliases.
* **`theme.sh` / `theme_colors.sh`**: Color layouts and CLI prompt custom styling.
* **`app-loader.sh`**: Scans and loads external app contributions and defines the `apps` registry manager.

### 📂 `network/` (Network Utilities)
* **`scan.sh`**: Defines the `scan` command for auditing:
  * `scan net` — Scan the local subnet for active SSH, Web, and database ports.
  * `scan sniff <ip>` — Check if a device is leaking plain-text traffic.
* **`adb_connect.sh`**: Defines the `adbcon` command (Wireless Debugging automatic connection/pairing and offline loopback locking).

### 📂 `user/` (User Shortcuts & Workspace)
* **`aliases.sh`**: Base aliases and functions:
  * `cd ws` / `cd dl` — Smart navigation to `/workspace` and `/Download` directories (via custom `cd()` function).
  * `re` — Reload the Zsh / Bash configurations instantly.
  * `up` — Package manager updater.
  * `cls` — Clear screen.
  * `..` / `...` — Navigate up one/two directory levels.
  * `path` — Print `$PATH` entries, one per line.
  * `kocr-app` / `kocr-res` — Jump shortcuts to Kaggle OCR project.
* **`tab_title.sh`**: Custom cross-shell compatible tab naming function.
* **`optimize.py`**: Background stability engine (see section below).
* **`optimize.sh`**: Shell wrapper alias for `optimize`.
* **`z-run.sh`**: Startup hook that runs a compact background stability check on each new interactive session.
* **`adb_utils.sh`**: High-value ADB integration commands:
  * `adb-sysinfo` — Displays battery, temp, device metrics, and CPU usage.
  * `adb-screengrab` — Captures screenshot, pulls it to path, and deletes tmp on phone.
  * `adb-logcat [filter]` — Streams system logs with optional search filtering.
  * `adb-audit [option]` — Runs the Device Security & Privacy Audit Engine. Running without options shows a usage menu.
    * Options:
      * `-a, --all`          Run full device security & privacy audit
      * `-s, --sideloads`    Scan for sideloaded/ADB-installed apps
      * `-d, --hidden`       Scan for running iconless background apps
      * `-p, --permissions`  Scan granted dangerous privacy permissions (categorized SMS, Microphone, Camera, GPS, etc.)
      * `-y, --system`       Scan active Device Administrators & Accessibility Services
      * `-i, --live`         Scan active Microphone, Camera, or Location access right now
  * `adb-manage [option]` — Unified application action & optimization dashboard. Running without options shows an interactive menu.
    * Options:
      * `-f, --freeze <pkg>`   Freeze (disable) an app completely
      * `-u, --unfreeze <pkg>` Unfreeze (enable) a frozen app
      * `-s, --standby <pkg>`  Tune app standby bucket state
      * `-e, --export <pkg>`   Extract and pull base APK file of an app
      * `-a, --autostart`      Manage boot-start autostart receivers

---

## 🔌 App Registration System

TER supports decoupled third-party app additions under `~/.shell.d/apps/`. Any repository or application can register itself as a shell extension by adding a subdirectory under `~/.shell.d/apps/<app-name>/`.

### Manifest File (`manifest.json`)
Each registered app should contain a `manifest.json` file in its registration directory. Example format:
```json
{
    "name": "NEXUS",
    "version": "6.1",
    "description": "Phone-to-Cloud Master Engine",
    "commands": ["nx", "ncd", "portal", "watch", "cld2lcl", "lcl2net", "cld2net", "sshubu", "fshare"]
}
```

### Component Files
Within `~/.shell.d/apps/<app-name>/`, you can drop:
- `*.sh` files (e.g. `aliases.sh`, `complete.sh`): These are automatically sourced on terminal startup.
- `welcome.hook`: A shell snippet contributing additional output to startup (currently unused but supported).

### Management Command
- `apps list` or `apps`: Displays all currently registered applications, versions, and commands.
- To uninstall/deregister an app, simply run: `rm -rf ~/.shell.d/apps/<app-name>`

---

## ⌨️ Custom Keyboard Layout (`~/.termux/termux.properties`)
Your touch keyboard has a custom extra-keys row with popups (swipe up on a key to trigger its macro):

| Normal Key | Swipe Up (Popup) Action | Purpose |
|:---|:---|:---|
| **DRAWER** | KEYBOARD | Open drawer / Toggle software keyboard |
| **TAB** | SHIFT TAB | Standard tab completion |
| **CTRL** | ALT | Terminal Control/Alt modifiers |
| **~** | `lcl2lan` | Auto-trigger local network bridge tunnel |
| **ESC** | `CTRL c` | Cancel/Exit running process |
| **/** | `exit` | Close active terminal session |
| **ssh** | `portal` | Tap: Connect to server `ubu` / Swipe: Open Nexus Portal |
| **PASTE** | `clear` | Tap: Paste clipboard / Swipe: Clear screen |
| **← / ↓ / →** | HOME / UP / END | Cursor navigation & command history |

---

## 📱 Drawer / Side Panel Naming (`~/.shell.d/user/tab_title.sh`)
The custom function `tabname()` dynamically renames the Termux side-drawer session tabs:
* **Usage:** Run `tabname <custom name>` to rename the current tab.
* **Auto-naming:** If run without arguments, it automatically detects the current directory name or active services and sets it as the tab title.

---

## ⚙️ Background Task & Stability Manager (`optimize`)

`optimize` is a background stability utility that exempts Termux from Android background constraints and runs tasks reliably.

### Startup Behavior
On every new interactive terminal session, a **compact one-line** stability summary is printed automatically:
```
⚙ BG  WakeLock:✓  Phantom:✓  Battery:✓  [STABLE]
```

### Commands

| Command | Description |
|:---|:---|
| `optimize status` | Quick compact stability audit (one-liner) |
| `optimize status -f` | Full detailed audit with descriptions (verbose box) |
| `optimize fix` | Optimize via ADB (phantom limit → 2048, battery whitelist) |
| `optimize run <name> <cmd>` | Launch command in background with WakeLock & logging |
| `optimize list` | List all active background tasks |
| `optimize stop <name>` | Terminate a running background task |
| `optimize log <name>` | Show log path and tail last 20 lines |
| `optimize -h` | Show full help with examples |

---

## 🚀 Installation

To deploy this environment configuration:
```bash
git clone <this-repo-url> ~/ter
bash ~/ter/install.sh
```
Then reload your terminal or run `re`.
