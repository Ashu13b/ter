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
| `adb-logcat` | Logging | Streams real-time Android logs with optional case-insensitive filter | `adb-logcat -h` |
| `adb-audit` | Security | Comprehensive device security, hidden app, and privacy sensor auditer | `adb-audit -h` |
| `termux-bg` | Stability | Safely configures background process stability & runs background tasks | `termux-bg -h` |
| `scan` | Security | Local subnet device discoverer, plain-text protocol sniffer, and vulnerability scanner | `scan -h` |
| `am` | Utility | Interactive shell alias manager (list, add, edit, reload) | `am -h` / `am --help` |
| `apps` | Registry | Termux plug-in app registry loader and manifest visualizer | `apps -h` |

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

### ⚙️ Background Stability Engine (`termux-bg`)
Manages the background runner system. Raises the Android Phantom Process limit safely to `2048` and whitelists Termux from battery optimization, ensuring that long-running processes (e.g. databases, SSH, servers) are never killed by Android.
```bash
# Audit background stability state (WakeLock, Phantom limit, Battery exemption)
termux-bg status

# Apply background optimizations (raised phantom limits and whitelist exemption)
termux-bg fix

# Start a command in background, keeping a CPU WakeLock
termux-bg run <task_name> "<command>"

# List all active background tasks running under WakeLocks
termux-bg list

# View logs or tail output for a background task
termux-bg log <task_name>
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

### 🛠️ Shell Alias Manager (`am`)
Handles interactive adding, modifying, and reloading of shell shortcuts.
```bash
# List all custom aliases
am list

# Add a new custom alias interactively
am add
```

### 🔌 App Registry (`apps`)
Queries installed modular plugins inside `~/.shell.d/apps/` and prints their commands and metadata.
```bash
# List all registered dynamic app plugins
apps list
```

---

> [!NOTE]
> All help flags can be executed completely offline. They bypass active ADB loopback connectivity checks so you can query commands and inspect usages without being connected to an Android device.
