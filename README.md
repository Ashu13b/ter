# 🌟 TER: Termux Custom Environment Manual

TER is a portable, independent Termux environment configuration repository. It installs a modular shell structure, dynamic welcome dashboard, custom keyboard layout, and a modular app-registration system. It works completely standalone or can be integrated with other projects (like NEXUS) via the registry system.

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
  * `c` — Clear screen, print current path, and list files.
  * `re` — Reload the Zsh / Bash configurations instantly.
  * `up` — Package manager updater.
  * `ws` / `dl` — Instant jumps to `/workspace` and `/Download` directories.
  * `kocr-app` / `kocr-res` — Jump shortcuts to Kaggle OCR project.
* **`welcome.sh`**: Renders the startup welcome dashboard and Operations Matrix.
* **`tab_title.sh`**: Custom cross-shell compatible tab naming function.
* **`adb_utils.sh`**: High-value ADB integration commands:
  * `adb-sysinfo` — Displays battery, temp, device metrics, and CPU usage.
  * `adb-screengrab` — Captures screenshot, pulls it to path, and deletes tmp on phone.
  * `adb-appmanage` — Menu-driven application freezing/lifecycle management.
  * `adb-logcat [filter]` — Streams system logs with optional search filtering.
  * `adb-audit-sideloads` — Scans for apps installed via ADB or untrusted sources (sideloaded).

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
- `welcome.sh`: A shell script contributing additional grid options or details to the central `welcome` Operations Matrix.

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

## 🚀 Installation

To deploy this environment configuration:
```bash
git clone <this-repo-url> ~/ter
bash ~/ter/install.sh
```
Then reload your terminal or run `re`.
