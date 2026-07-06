# TER OS: Command Line Interface Manual & Utility Guide

Welcome to the command line interface guide for the unified **TER OS** Termux environment. All custom utilities support offline `-h` and `--help` flags to display comprehensive usage guides.

---

## 1. Commands Overview

| Command | Category | Description | Help Command |
| :--- | :--- | :--- | :--- |
| `adbcon` | Network | Wireless ADB loopback configuration & tunnel manager | `adbcon -h` / `adbcon --help` |
| `adb-sysinfo` | System | Audits device specs, battery level, temp, and top CPU processes | `adb-sysinfo -h` |
| `adb-screengrab` | System | Instantly captures device screen, pulls image, and opens viewer | `adb-screengrab -h` |
| `adb-manage` | Operations | Consolidated app management, standby controller, freezing, and APK export | `adb-manage -h` |
| `adb-apk` | Operations | Smart APK sideloader: fuzzy pick, batch install, aapt preview, friendly errors, optional launch | `adb-apk -h` |
| `adb-logcat` | Logging | Streams real-time Android logs with optional case-insensitive filter | `adb-logcat -h` |
| `adb-audit` | Security | Comprehensive device security, hidden app, and privacy sensor auditer | `adb-audit -h` |
| `dvop` | System | Toggles `development_settings_enabled` via ADB (on/off/toggle/status). `dvop off` confirms first — see caveat in README | `dvop status` |
| `optimize` | Stability | Safely configures background process stability & runs background tasks | `optimize -h` |
| `scan` | Security | Local subnet device discoverer, plain-text protocol sniffer, and vulnerability scanner | `scan -h` |
| `alm` | Utility | Interactive shell alias manager (list, add, edit, reload) | `alm -h` / `alm --help` |
| `apps` | Registry | Termux plug-in app registry loader and manifest visualizer | `apps -h` |
| `ter` | System | Master Controller dashboard and interactive theme switcher | `ter -h` / `ter --help` |

---

## 2. Command Details & Offline Usage Guides

### 🛰️ ADB Loopback Connection Manager (`adbcon`)
Handles wireless ADB connections over local Wi-Fi, scans for active debugging ports automatically, routes them to a local offline loopback (`127.0.0.1:5555`), and opens a device shell.

```bash
# Display connection help manual
adbcon -h

# Disconnect active ADB sessions and clean up local ADB server daemons
adbcon -d
```

### 📱 Device Metrics & System Info (`adb-sysinfo`)
Queries the connected device via ADB loopback to fetch and display hardware model details, Android version, charge status/battery temp, and top CPU consumer processes.
```bash
adb-sysinfo -h
```

### 📸 Screenshot Grabber (`adb-screengrab`)
Grabs the screen image from the phone, pulls the PNG file locally with a timestamp prefix, deletes the remote temporary file, and opens it using the default system viewer.
```bash
adb-screengrab -h
```

### 📦 Consolidated App Manager (`adb-manage`)
Allows optimizing application standby buckets, disabling (freezing) apps to prevent them from running, and pulling/exporting raw APK installer files.
```bash
# Access the interactive menu dashboard
adb-manage

# Run automated safe background optimization
adb-manage -o

# Freeze / Disable a background hogging application
adb-manage -f <package_name>

# Unfreeze / Enable an application
adb-manage -u <package_name>
```

### 📦 Smart APK Installer (`adb-apk`)
Fuzzy-picks APKs from `~/storage/downloads`, `/storage/emulated/0/workspace`, and `$HOME`, previews package info with `aapt`, installs one or many, translates `INSTALL_FAILED_*` errors into plain English, and optionally launches the app after install.
```bash
# Bare — fzf browser over Downloads / workspace / cwd
adb-apk

# Fuzzy search by name across the same paths
adb-apk chrome

# Install one or many APK files
adb-apk app.apk
adb-apk *.apk

# Reinstall keeping app data (signature must match)
adb-apk -r app.apk

# Force / skip confirmation prompt
adb-apk -f app.apk
```
Requires `fzf` for the browser mode. `dvop off` will kill the ADB
channel — run `adbcon` first, and if you toggled dvop off see the
recovery ladder printed by `adbcon`.

### 🛠️ Developer Options Toggle (`dvop`)
Flips the Android `development_settings_enabled` global via the current ADB session — hides Developer Options from banking / Play-Integrity / GPS-spoof checks with no phone reboot.
```bash
dvop status        # ON / OFF
dvop on            # show Developer Options in Settings
dvop off           # hide — prompts because Wireless Debugging dies with it
dvop off -y        # skip the confirmation prompt
dvop toggle        # flip whichever way makes sense
```
⚠ `dvop off` also disables Wireless Debugging → your ADB session dies. Recovery: on the phone re-enable Developer Options + Wireless Debugging, then run `adbcon`. See `docs/dvop-experiment-findings.md` for the full write-up on why no CLI-only self-recovery is possible on OxygenOS 15.

### 📋 Real-Time Log Viewer (`adb-logcat`)
Streams Android system logs in real time. Can optionally filter stream lines by keywords.
```bash
# Stream all system logs
adb-logcat

# Stream log lines matching "Camera" (case-insensitive)
adb-logcat camera
```

### 🛡️ Master Security & Privacy Audit Engine (`adb-audit`)
Conducts security scans for sideloaded/ADB-installed apps, iconless hidden packages running in the background, dangerous permissions, and checks active camera/microphone/GPS sensor accesses.
```bash
# Run full system security audit
adb-audit -a

# Find running iconless hidden background apps
adb-audit -d

# Check if any application is actively using the Microphone/Camera right now
adb-audit -i
```

### ⚙️ Background Stability Engine (`optimize`)
Manages the background runner system. Raises the Android Phantom Process limit safely to `2048` and whitelists Termux from battery optimization, ensuring that long-running processes (e.g. databases, SSH, servers) are never killed by Android.
```bash
# Audit background stability state (WakeLock, Phantom limit, Battery exemption)
optimize status

# Apply background optimizations (raised phantom limits and whitelist exemption)
optimize fix

# Start a command in background, keeping a CPU WakeLock
optimize run <task_name> "<command>"

# List all active background tasks running under WakeLocks
optimize list

# View logs or tail output for a background task
optimize log <task_name>
```

### 📡 Network Scanner (`scan`)
Probes local subnets, audits IP addresses for open plain-text channels, and audits common vulnerable services.
```bash
# Discover other devices on the current network
scan net

# Audit plain-text channels (FTP, Telnet, HTTP, POP3) on a host
scan sniff <ip_address>

# Scan common risk ports (SSH, ADB, VNC, HTTP-Alt)
scan vuln <ip_address>
```

### 🛠️ Shell Alias Manager (`alm`)
Handles interactive adding, modifying, and reloading of shell shortcuts. Renamed from `am` to avoid confusion with Android's Activity Manager (`am start …` inside `adb shell`).
```bash
# List all custom aliases
alm list

# Add a new custom alias interactively
alm add
```

### 🔌 App Registry (`apps`)
Queries installed modular plugins inside `~/.shell.d/apps/` and prints their commands and metadata.
```bash
# List all registered dynamic app plugins
apps list
```

### ⚙️ Master Controller & Theme Switcher (`ter`)
Launches the interactive settings panel for system startup configuration and provides an eye-preserving theme switcher menu.
```bash
# Open the master settings dashboard (indicates active theme)
ter

# Switch tmux themes interactively
ter theme

# Toggle autostart of tmux session
ter toggle tmux
```

---

## 3. Troubleshooting & Common Issues

### ❌ Linker Symbol Errors on `adb` (protobuf / abseil-cpp mismatch)

If running `adb` or `adb-apk` fails with a linker error similar to:
* `CANNOT LINK EXECUTABLE "adb": cannot locate symbol "...protobuf..."`
* `cannot locate symbol "...abseil..." referenced by "libprotobuf.so"`

**Why it happens:**
This is a standard Termux packaging sync mismatch. A package upgrade has updated `android-tools` (which contains `adb`) to a version built against newer libraries, but your local shared libraries (`libprotobuf` and `abseil-cpp`) were not automatically upgraded to their matching versions.

**How to fix it:**
Run the following package upgrade commands in your Termux shell to sync the dependencies to their latest repository builds:

```bash
# Upgrade the core protobuf library
apt install -y libprotobuf

# Upgrade the abseil-cpp library dependency
apt install -y abseil-cpp
```

Once upgraded, verify that the linker errors are resolved by running:
```bash
adb version
```

---

> [!NOTE]
> All help flags can be executed completely offline. They bypass active ADB loopback connectivity checks so you can query commands and inspect usages without being connected to an Android device.
