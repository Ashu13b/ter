# ── TER OS: ADB-Powered System Utilities ──

# ── 1. Device System Metrics ──
adb-sysinfo() {
    if ! adb devices | grep -q "127.0.0.1:5555[[:space:]]*device"; then
        echo -e "${C_RED}❌ ADB loopback is offline. Run adbcon first.${C_RESET}"
        return 1
    fi
    
    echo -e "\n${C_BOLD}${C_CYAN}─── DEVICE SYSTEM METRICS ───${C_RESET}"
    local model; model=$(adb -s 127.0.0.1:5555 shell getprop ro.product.model | tr -d '\r')
    local android_ver; android_ver=$(adb -s 127.0.0.1:5555 shell getprop ro.build.version.release | tr -d '\r')
    
    # Parse battery status
    local battery_info; battery_info=$(adb -s 127.0.0.1:5555 shell dumpsys battery 2>/dev/null | tr -d '\r')
    local level; level=$(echo "$battery_info" | grep -E "^\s*level:" | awk '{print $2}')
    local temp; temp=$(echo "$battery_info" | grep -E "^\s*temperature:" | awk '{print $2}')
    local temp_c; temp_c=$(python3 -c "print($temp / 10.0)" 2>/dev/null || echo "?")
    local status_code; status_code=$(echo "$battery_info" | grep -E "^\s*status:" | awk '{print $2}')
    
    local batt_status="Unknown"
    case "$status_code" in
        2) batt_status="Charging" ;;
        3) batt_status="Discharging" ;;
        4) batt_status="Not Charging" ;;
        5) batt_status="Full" ;;
    esac
    
    # Parse CPU top processes
    local cpu_load; cpu_load=$(adb -s 127.0.0.1:5555 shell top -n 1 -m 5 2>/dev/null | grep -E "%" | head -n 5)

    echo -e "  ${C_BOLD}Model:${C_RESET} ${C_YELLOW}$model${C_RESET} (Android $android_ver)"
    echo -e "  ${C_BOLD}Battery:${C_RESET} ${C_GREEN}${level}%${C_RESET} | Temp: ${C_BLUE}${temp_c}°C${C_RESET} | Status: ${C_CYAN}$batt_status${C_RESET}"
    echo -e "\n  ${C_BOLD}${C_MAGENTA}Top CPU Consuming Processes:${C_RESET}"
    if [ -n "$cpu_load" ]; then
        echo "$cpu_load" | sed 's/^/  /'
    else
        echo "  (No process data returned)"
    fi
    echo ""
}

# ── 2. Instantly Grab Screenshot ──
adb-screengrab() {
    if ! adb devices | grep -q "127.0.0.1:5555[[:space:]]*device"; then
        echo -e "${C_RED}❌ ADB loopback is offline. Run adbcon first.${C_RESET}"
        return 1
    fi
    
    local filename="screenshot_$(date +%Y%m%d_%H%M%S).png"
    local local_dir; local_dir=$(pwd)
    
    echo -e "📸 Capturing phone screen..."
    adb -s 127.0.0.1:5555 shell screencap -p /sdcard/Download/tmp_screenshot.png
    
    echo -e "📥 Pulling image to workspace..."
    adb -s 127.0.0.1:5555 pull /sdcard/Download/tmp_screenshot.png "$local_dir/$filename" >/dev/null 2>&1
    adb -s 127.0.0.1:5555 shell rm /sdcard/Download/tmp_screenshot.png
    
    echo -e "🎉 Screenshot saved in local folder as: ${C_GREEN}$filename${C_RESET}"
    if command -v termux-open &>/dev/null; then
        termux-open "$local_dir/$filename"
    fi
}

# ── 3. App Lifecycle Manager (Freeze/Unfreeze) ──
adb-appmanage() {
    if ! adb devices | grep -q "127.0.0.1:5555[[:space:]]*device"; then
        echo -e "${C_RED}❌ ADB loopback is offline. Run adbcon first.${C_RESET}"
        return 1
    fi

    echo -e "\n${C_BOLD}${C_CYAN}─── APP LIFECYCLE MANAGER ───${C_RESET}"
    echo " [1] List installed third-party apps"
    echo " [2] Freeze an app (Disable background battery drain)"
    echo " [3] Unfreeze an app (Re-enable app access)"
    echo -n "👉 Selection (1-3): "
    read choice
    
    case "$choice" in
        1)
            echo -e "\n📦 Installed Third-Party Packages:"
            adb -s 127.0.0.1:5555 shell pm list packages -3 | tr -d '\r' | cut -d':' -f2 | sort | sed 's/^/  /'
            ;;
        2)
            echo -n "👉 Enter package name to freeze: "
            read pkg
            if [ -n "$pkg" ]; then
                echo -e "❄️ Freezing package $pkg..."
                adb -s 127.0.0.1:5555 shell pm disable-user "$pkg"
                echo -e "✅ Package disabled. It will not run or consume battery."
            fi
            ;;
        3)
            echo -n "👉 Enter package name to unfreeze: "
            read pkg
            if [ -n "$pkg" ]; then
                echo -e "🔥 Unfreezing package $pkg..."
                adb -s 127.0.0.1:5555 shell pm enable "$pkg"
                echo -e "✅ Package enabled."
            fi
            ;;
        *)
            echo "❌ Invalid choice."
            ;;
    esac
    echo ""
}

# ── 4. Silent Background APK Installer (DISABLED FOR SECURITY) ──
# adb-install() {
#     echo -e "${C_RED}⚠️ adb-install has been disabled for security reasons.${C_RESET}"
#     echo -e "If you want to re-enable it, edit your ~/.shell.d/user/adb_utils.sh file."
#     return 1
# }

# ── 5. System Logcat Streamer & Filter ──
adb-logcat() {
    if ! adb devices | grep -q "127.0.0.1:5555[[:space:]]*device"; then
        echo -e "${C_RED}❌ ADB loopback is offline. Run adbcon first.${C_RESET}"
        return 1
    fi
    if [ -n "$1" ]; then
        echo -e "📋 Streaming system logs for filter: ${C_YELLOW}$1${C_RESET} (Press Ctrl+C to exit)..."
        adb -s 127.0.0.1:5555 logcat | grep -i "$1"
    else
        echo -e "📋 Streaming system logs (Press Ctrl+C to exit)..."
        adb -s 127.0.0.1:5555 logcat
    fi
}

# ── 6. Master Security & Privacy Audit Engine ──
adb-audit() {
    if ! adb devices | grep -q "127.0.0.1:5555[[:space:]]*device"; then
        echo -e "${C_RED}❌ ADB loopback is offline. Run adbcon first.${C_RESET}"
        return 1
    fi

    python3 - "$1" << 'EOF'
import subprocess, re, sys

C_BOLD = "\033[1m"
C_RED = "\033[1;31m"
C_GREEN = "\033[1;32m"
C_YELLOW = "\033[1;33m"
C_CYAN = "\033[1;36m"
C_MAGENTA = "\033[1;35m"
C_RESET = "\033[0m"
C_DIM = "\033[2m"

DANGEROUS_PERMS = {
    "android.permission.RECORD_AUDIO": ("Microphone", C_RED),
    "android.permission.CAMERA": ("Camera", C_RED),
    "android.permission.ACCESS_FINE_LOCATION": ("GPS Location", C_YELLOW),
    "android.permission.READ_SMS": ("Read SMS (2FA Risk)", C_RED),
    "android.permission.RECEIVE_SMS": ("Receive SMS (2FA Risk)", C_RED),
    "android.permission.SYSTEM_ALERT_WINDOW": ("Draw Over Apps (Overlay Risk)", C_YELLOW),
    "android.permission.READ_CALL_LOG": ("Call Logs", C_DIM),
    "android.permission.READ_CONTACTS": ("Contacts", C_DIM),
}

def run_adb(args):
    cmd = ["adb", "-s", "127.0.0.1:5555"] + args
    try:
        return subprocess.check_output(cmd, stderr=subprocess.DEVNULL).decode("utf-8").replace('\r', '')
    except Exception:
        return ""

def get_third_party_packages():
    out = run_adb(["shell", "pm list packages -i -3"])
    packages = []
    for line in out.splitlines():
        if line.strip().startswith("package:"):
            parts = line.strip().split()
            pkg = parts[0].split(':')[1]
            inst = parts[1].split('=')[1] if len(parts) > 1 else "Unknown"
            packages.append((pkg, inst))
    return packages

def audit_sideloads(packages):
    print(f"\n{C_CYAN}─── 1. SIDELOADED / ADB INSTALLATION AUDIT ───{C_RESET}")
    flagged = []
    for pkg, inst in packages:
        if inst in ["null", "Unknown", ""]:
            flagged.append((pkg, inst))
            
    if flagged:
        print(f"{C_YELLOW}⚠️  Detected apps sideloaded via ADB or manual APK files:{C_RESET}")
        for pkg, inst in flagged:
            print(f"  • {C_RED}{pkg}{C_RESET} (Installer: {C_DIM}{inst if inst else 'null'}{C_RESET})")
    else:
        print(f"{C_GREEN}✔ All third-party apps were installed via trusted store sources.{C_RESET}")

def audit_hidden(packages):
    print(f"\n{C_CYAN}─── 2. RUNNING ICONLESS BACKGROUND APPS ───{C_RESET}")
    out_launch = run_adb(["shell", "cmd package query-activities -a android.intent.action.MAIN -c android.intent.category.LAUNCHER"])
    launcher_pkgs = set(re.findall(r"packageName=([a-zA-Z0-9._]+)", out_launch))
    
    out_ps = run_adb(["shell", "ps -A"])
    running_pkgs = set()
    for line in out_ps.splitlines():
        parts = line.split()
        if len(parts) >= 9:
            uid, proc_name = parts[0], parts[-1]
            if uid.startswith("u0_a"):
                running_pkgs.add(proc_name.split(':')[0])
                
    third_party_names = set(pkg for pkg, _ in packages)
    flagged = []
    for pkg in sorted(running_pkgs):
        if pkg in third_party_names and pkg not in launcher_pkgs and pkg != "com.termux":
            flagged.append(pkg)
            
    if flagged:
        print(f"{C_YELLOW}⚠️  Detected running background apps with NO launcher app drawer icon:{C_RESET}")
        for pkg in flagged:
            print(f"  • {C_RED}{pkg}{C_RESET}")
        print(f"\n{C_DIM}Note: These may be legitimate keyboards/services, but hidden background run is a common spyware pattern.{C_RESET}")
    else:
        print(f"{C_GREEN}✔ No suspicious iconless background apps detected running.{C_RESET}")

def audit_permissions(packages):
    print(f"\n{C_CYAN}─── 3. PRIVACY & SENSITIVE PERMISSIONS AUDIT ───{C_RESET}")
    print(f"{C_DIM}Scanning third-party apps for critical permission grants (Camera, Mic, SMS, GPS)...{C_RESET}\n")
    
    apps_with_perms = {}
    for pkg, _ in packages:
        if pkg == "com.termux":
            continue
        dumpsys = run_adb(["shell", "dumpsys package", pkg])
        
        granted = []
        for line in dumpsys.splitlines():
            line = line.strip()
            match = re.search(r"([a-zA-Z0-9._]+permission[a-zA-Z0-9._]+):\s*granted=true", line)
            if match:
                perm = match.group(1)
                if perm in DANGEROUS_PERMS:
                    granted.append(perm)
                    
        if granted:
            apps_with_perms[pkg] = list(set(granted))
            
    if apps_with_perms:
        for pkg, perms in sorted(apps_with_perms.items()):
            print(f"  • {C_BOLD}{pkg}{C_RESET}")
            for perm in sorted(perms):
                name, color = DANGEROUS_PERMS[perm]
                print(f"    - {color}{name:<32}{C_RESET} {C_DIM}({perm}){C_RESET}")
    else:
        print(f"{C_GREEN}✔ No third-party apps hold high-risk privacy permissions.{C_RESET}")

def audit_system_security():
    print(f"\n{C_CYAN}─── 4. ELEVATED PRIVILEGES & SERVICES AUDIT ───{C_RESET}")
    
    dpm_out = run_adb(["shell", "dumpsys device_policy"])
    admins = []
    in_section = False
    for line in dpm_out.splitlines():
        if "Enabled Device Admins" in line:
            in_section = True
            continue
        if in_section:
            if line.startswith("  ") and not line.startswith("    "):
                in_section = False
            elif "ComponentInfo" in line or "/" in line:
                admins.append(line.strip())
                
    if admins:
        print(f"  {C_YELLOW}⚠️  Enabled Device Administrators (Can wipe phone / lock settings):{C_RESET}")
        for admin in admins:
            print(f"    • {C_RED}{admin}{C_RESET}")
    else:
        print(f"  {C_GREEN}✔ No active Device Administrator apps.{C_RESET}")
        
    acc_out = run_adb(["shell", "settings get secure enabled_accessibility_services"]).strip()
    if acc_out and acc_out != "null" and acc_out != "":
        services = acc_out.split(':')
        print(f"\n  {C_YELLOW}⚠️  Active Accessibility Services (Can read screen / simulate clicks):{C_RESET}")
        for srv in services:
            print(f"    • {C_RED}{srv}{C_RESET}")
    else:
        print(f"\n  {C_GREEN}✔ No active Accessibility Services (Screen-readers/Trojans).{C_RESET}")

def run_all_audits():
    arg = sys.argv[1] if len(sys.argv) > 1 else ""
    packages = get_third_party_packages()
    
    if arg in ["sideloads", "hidden", "permissions", "system"]:
        if arg == "sideloads":
            audit_sideloads(packages)
        elif arg == "hidden":
            audit_hidden(packages)
        elif arg == "permissions":
            audit_permissions(packages)
        elif arg == "system":
            audit_system_security()
    else:
        print(f"\n{C_BOLD}{C_MAGENTA}============================================================{C_RESET}")
        print(f"          {C_BOLD}TER OS: SECURITY AND PRIVACY AUDIT ENGINE{C_RESET}")
        print(f"{C_BOLD}{C_MAGENTA}============================================================{C_RESET}")
        audit_sideloads(packages)
        audit_hidden(packages)
        audit_permissions(packages)
        audit_system_security()
        print(f"\n{C_BOLD}{C_MAGENTA}============================================================{C_RESET}\n")

if __name__ == '__main__':
    run_all_audits()
EOF
}

# ── Backwards Compatible Aliases ──
adb-audit-sideloads() { adb-audit sideloads; }
adb-audit-hidden() { adb-audit hidden; }
