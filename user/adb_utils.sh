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
    
    if [[ -z "$1" ]] || [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
        echo -e "${C_BOLD}${C_CYAN}─── TER OS: ADB-Powered Security Audit ───${C_RESET}"
        echo -e "Usage: adb-audit [option]\n"
        echo -e "Options:"
        echo -e "  -a, --all          Run full device security & privacy audit"
        echo -e "  -s, --sideloads    Scan for sideloaded/ADB-installed apps"
        echo -e "  -d, --hidden       Scan for running iconless background apps"
        echo -e "  -p, --permissions  Scan granted dangerous privacy permissions (categorized & chunked)"
        echo -e "  -y, --system       Scan active Device Administrators & Accessibility Services"
        echo -e "  -i, --live         Scan active Microphone, Camera, or Location access right now"
        echo ""
        return 0
    fi
    
    local key="$1"
    case "$key" in
        -a|--all) key="all" ;;
        -s|--sideloads) key="sideloads" ;;
        -d|--hidden) key="hidden" ;;
        -p|--permissions) key="permissions" ;;
        -y|--system) key="system" ;;
        -i|--live) key="live" ;;
        *)
            echo -e "${C_RED}❌ Invalid option: $1${C_RESET}"
            echo -e "Run 'adb-audit' without arguments to see usage help."
            return 1
            ;;
    esac

    python3 - "$key" << 'EOF'
import subprocess, re, sys

C_BOLD = "\033[1m"
C_RED = "\033[1;31m"
C_GREEN = "\033[1;32m"
C_YELLOW = "\033[1;33m"
C_CYAN = "\033[1;36m"
C_MAGENTA = "\033[1;35m"
C_RESET = "\033[0m"
C_DIM = "\033[2m"

def run_adb(args):
    cmd = ["adb", "-s", "127.0.0.1:5555"] + args
    try:
        return subprocess.check_output(cmd, stderr=subprocess.DEVNULL).decode("utf-8", errors="ignore").replace('\r', '')
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

def get_running_packages():
    out_ps = run_adb(["shell", "ps -A"])
    running_pkgs = set()
    for line in out_ps.splitlines():
        parts = line.split()
        if len(parts) >= 9:
            uid, proc_name = parts[0], parts[-1]
            if uid.startswith("u0_a") or uid.startswith("u0_i") or uid.startswith("system"):
                pkg = proc_name.split(':')[0]
                running_pkgs.add(pkg)
    return running_pkgs

def get_foreground_app():
    out = run_adb(["shell", "dumpsys window"])
    match = re.search(r"mFocusedApp=ActivityRecord\{\S+\s+\S+\s+([a-zA-Z0-9._]+)", out)
    if match:
        return match.group(1)
    match = re.search(r"mCurrentFocus=Window\{\S+\s+\S+\s+([a-zA-Z0-9._]+)", out)
    if match:
        return match.group(1)
    return ""

def get_active_cameras():
    cam_out = run_adb(["shell", "dumpsys media.camera"])
    active_cams = []
    in_section = False
    for line in cam_out.splitlines():
        if "Active Camera Clients:" in line:
            in_section = True
            continue
        if in_section:
            if line.startswith("==") or line.strip() == "":
                in_section = False
            else:
                match = re.search(r"package\s+([a-zA-Z0-9._]+)", line)
                if match:
                    active_cams.append(match.group(1))
                else:
                    pkgs = re.findall(r"([a-zA-Z0-9._]+)\.pid", line)
                    active_cams.extend(pkgs)
    return list(set(active_cams))

def get_active_ops(op_name):
    out = run_adb(["shell", "cmd appops query-op", op_name]).strip()
    active = []
    if out:
        for line in out.splitlines():
            if "Package" in line:
                match = re.search(r"Package\s+([a-zA-Z0-9._]+):", line)
                if match:
                    active.append(match.group(1))
            else:
                pkg = line.strip()
                if pkg:
                    active.append(pkg)
    return active

def parse_dumpsys_package(dumpsys_pkg_out):
    pkg_permissions = {}
    current_pkg = None
    current_user = 0
    
    for line in dumpsys_pkg_out.splitlines():
        pkg_match = re.match(r"^\s*Package\s+\[([a-zA-Z0-9._]+)\]", line)
        if pkg_match:
            current_pkg = pkg_match.group(1)
            pkg_permissions[current_pkg] = {}
            current_user = 0
            continue
            
        if current_pkg:
            user_match = re.match(r"^\s*User\s+(\d+):", line)
            if user_match:
                current_user = int(user_match.group(1))
                continue
                
            if current_user == 0:
                perm_match = re.match(r"^\s*([a-zA-Z0-9._]+): granted=(true|false)(?:,\s*flags=\[([^\]]*)\])?", line)
                if perm_match:
                    perm_name = perm_match.group(1)
                    granted = perm_match.group(2) == "true"
                    flags_str = perm_match.group(3) or ""
                    flags = [f.strip() for f in flags_str.split('|') if f.strip()]
                    pkg_permissions[current_pkg][perm_name] = {
                        "granted": granted,
                        "flags": flags
                    }
    return pkg_permissions

def parse_dumpsys_appops(dumpsys_ops_out):
    pkg_ops = {}
    current_uid = None
    current_pkg = None
    current_op = None
    
    for line in dumpsys_ops_out.splitlines():
        uid_match = re.match(r"^\s*Uid\s+(\S+):", line)
        if uid_match:
            current_uid = uid_match.group(1)
            current_pkg = None
            current_op = None
            continue
            
        pkg_match = re.match(r"^\s*Package\s+([a-zA-Z0-9._]+):", line)
        if pkg_match:
            current_pkg = pkg_match.group(1)
            current_op = None
            if current_pkg not in pkg_ops:
                pkg_ops[current_pkg] = {}
            continue
            
        if current_pkg:
            op_match = re.match(r"^\s*([A-Z_]+)\s+\((\w+)\):", line)
            if op_match:
                current_op = op_match.group(1)
                mode = op_match.group(2)
                pkg_ops[current_pkg][current_op] = {
                    "mode": mode,
                    "last_accessed": None,
                    "duration": None
                }
                continue
                
            if current_op:
                access_match = re.search(r"Access:\s+\[\S+\]\s+\S+\s+\S+\s+\((-[^)]+)\)", line)
                if access_match:
                    rel_time = access_match.group(1).lstrip('-')
                    if pkg_ops[current_pkg][current_op]["last_accessed"] is None:
                        pkg_ops[current_pkg][current_op]["last_accessed"] = rel_time
                        
                    dur_match = re.search(r"duration=\+?([a-zA-Z0-9ms]+)", line)
                    if dur_match:
                        if pkg_ops[current_pkg][current_op]["duration"] is None:
                            pkg_ops[current_pkg][current_op]["duration"] = dur_match.group(1)
    return pkg_ops

def format_time_ago(time_str):
    if not time_str:
        return "Never"
    time_str = time_str.lstrip('-').lstrip('+')
    parts = re.findall(r'\d+[a-zA-Z]+', time_str)
    if len(parts) > 1:
        parts = [p for p in parts if not p.endswith('ms')]
    return " ".join(parts) + " ago"

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
    print(f"{C_DIM}Gathering system states... (This may take a moment){C_RESET}")
    
    dumpsys_pkg_out = run_adb(["shell", "dumpsys package"])
    dumpsys_ops_out = run_adb(["shell", "dumpsys appops"])
    running_pkgs = get_running_packages()
    foreground_pkg = get_foreground_app()
    active_mics = get_active_ops("android:record_audio")
    active_cams = get_active_cameras()
    active_locs = get_active_ops("android:fine_location")
    
    pkg_perms = parse_dumpsys_package(dumpsys_pkg_out)
    pkg_ops = parse_dumpsys_appops(dumpsys_ops_out)
    
    third_party_names = {pkg for pkg, _ in packages if pkg != "com.termux"}
    
    categories = [
        {
            "name": "SMS Access (Read/Receive/Send SMS)",
            "risk": "2FA Intercept / Leak of Private Messages",
            "perms": ["android.permission.READ_SMS", "android.permission.RECEIVE_SMS", "android.permission.SEND_SMS"],
            "ops": ["READ_SMS", "RECEIVE_SMS", "SEND_SMS"],
            "color": C_RED
        },
        {
            "name": "Microphone Access (Record Audio)",
            "risk": "Silent Background Environmental Eavesdropping",
            "perms": ["android.permission.RECORD_AUDIO"],
            "ops": ["RECORD_AUDIO"],
            "color": C_RED
        },
        {
            "name": "Camera Access (Take Pictures & Video)",
            "risk": "Silent Background Spy Photos & Video Recordings",
            "perms": ["android.permission.CAMERA"],
            "ops": ["CAMERA"],
            "color": C_RED
        },
        {
            "name": "Location Access (GPS & Network Location)",
            "risk": "Real-Time Silent Tracking of Device Location",
            "perms": ["android.permission.ACCESS_FINE_LOCATION", "android.permission.ACCESS_COARSE_LOCATION"],
            "ops": ["FINE_LOCATION", "COARSE_LOCATION"],
            "color": C_YELLOW
        },
        {
            "name": "Draw Over Apps (Overlay Alert Window)",
            "risk": "Overlay Phishing Attacks / Clickjacking Attempts",
            "perms": ["android.permission.SYSTEM_ALERT_WINDOW"],
            "ops": ["SYSTEM_ALERT_WINDOW"],
            "color": C_YELLOW
        },
        {
            "name": "Contacts & Call Logs Access",
            "risk": "Harvesting Contacts List / Spy Call Logging",
            "perms": ["android.permission.READ_CONTACTS", "android.permission.WRITE_CONTACTS", "android.permission.READ_CALL_LOG"],
            "ops": ["READ_CONTACTS", "WRITE_CONTACTS", "READ_CALL_LOG"],
            "color": C_DIM
        }
    ]
    
    print(f"\n{C_DIM}Scanning {len(third_party_names)} third-party apps for critical privacy permissions...{C_RESET}\n")
    
    for cat in categories:
        print(f"{cat['color']}{C_BOLD}📁 {cat['name']}{C_RESET}")
        print(f"   {C_DIM}Risk: {cat['risk']}{C_RESET}")
        
        cat_apps = []
        for pkg in sorted(third_party_names):
            granted_perms = []
            one_time_granted = False
            
            p_info = pkg_perms.get(pkg, {})
            for perm in cat["perms"]:
                if p_info.get(perm, {}).get("granted", False):
                    granted_perms.append(perm)
                    flags = p_info.get(perm, {}).get("flags", [])
                    if any("ONE_TIME" in f for f in flags):
                        one_time_granted = True
            
            if not granted_perms:
                continue
                
            perm_type = "Foreground-Only (While in use)"
            if one_time_granted:
                perm_type = f"{C_MAGENTA}One-Time (Temporary){C_RESET}"
            elif cat["name"].startswith("SMS") or cat["name"].startswith("Contacts") or cat["name"].startswith("Draw"):
                perm_type = "Always (Background & Foreground)"
            elif cat["name"].startswith("Location"):
                bg_granted = p_info.get("android.permission.ACCESS_BACKGROUND_LOCATION", {}).get("granted", False)
                if bg_granted:
                    perm_type = "Always (Background & Foreground)"
                else:
                    perm_type = "Foreground-Only (While in use)"
            
            is_active = False
            active_msg = ""
            if cat["name"].startswith("Microphone") and pkg in active_mics:
                is_active = True
                active_msg = f" {C_RED}{C_BOLD}[🔴 ACTIVELY RECORDING AUDIO RIGHT NOW!]{C_RESET}"
            elif cat["name"].startswith("Camera") and pkg in active_cams:
                is_active = True
                active_msg = f" {C_RED}{C_BOLD}[🔴 ACTIVELY RECORDING VIDEO/PHOTO RIGHT NOW!]{C_RESET}"
            elif cat["name"].startswith("Location") and pkg in active_locs:
                is_active = True
                active_msg = f" {C_RED}{C_BOLD}[🔴 ACTIVELY TRACKING GPS LOCATION RIGHT NOW!]{C_RESET}"
                
            is_focused = (pkg == foreground_pkg)
            is_running = (pkg in running_pkgs)
            
            state_desc = ""
            if is_focused:
                state_desc = f"{C_GREEN}📱 Currently in Foreground (Active){C_RESET}"
            elif is_running:
                if is_active:
                    state_desc = f"{C_RED}⚠️ Running in Background & Sensor Active!{C_RESET}"
                else:
                    if perm_type.startswith("Always"):
                        state_desc = f"{C_YELLOW}⚠️ Running in Background (Can access silently){C_RESET}"
                    else:
                        state_desc = f"{C_DIM}⚠️ Running in Background (Idle, foreground service needed for sensor access){C_RESET}"
            else:
                state_desc = f"{C_DIM}💤 Not running (Safe){C_RESET}"
                
            latest_time = None
            latest_duration = None
            
            ops_info = pkg_ops.get(pkg, {})
            for op in cat["ops"]:
                op_data = ops_info.get(op, {})
                t = op_data.get("last_accessed")
                if t:
                    latest_time = t
                    latest_duration = op_data.get("duration")
                    
            access_str = ""
            if latest_time:
                formatted_time = format_time_ago(latest_time)
                dur_str = f" for {latest_duration}" if latest_duration else ""
                access_str = f"\n      {C_DIM}↳ Last accessed: {formatted_time}{dur_str}{C_RESET}"
                
            installer = next((inst for p, inst in packages if p == pkg), "Unknown")
            sideload_tag = f" {C_YELLOW}(Sideloaded){C_RESET}" if installer in ["null", "Unknown", ""] else ""
            
            app_line = f"  • {C_BOLD}{pkg}{C_RESET}{sideload_tag}\n    - Scope: {C_CYAN}{perm_type}{C_RESET} | State: {state_desc}{active_msg}{access_str}"
            cat_apps.append(app_line)
            
        if cat_apps:
            for app_line in cat_apps:
                print(app_line)
        else:
            print(f"  {C_GREEN}✔ No apps hold this permission.{C_RESET}")
        print()

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

def audit_live_access():
    print(f"\n{C_CYAN}─── 5. ACTIVE PRIVACY MONITOR (LIVE ACCESS) ───{C_RESET}")
    print(f"{C_DIM}Checking if any app is accessing Microphone, Camera, or GPS RIGHT NOW...{C_RESET}\n")
    
    active_cams = get_active_cameras()
    active_mics = get_active_ops("android:record_audio")
    active_locs = get_active_ops("android:fine_location")
    
    active_ops = []
    for pkg in active_mics:
        active_ops.append((pkg, "🎙️ Microphone"))
    for pkg in active_cams:
        active_ops.append((pkg, "📸 Camera"))
    for pkg in active_locs:
        active_ops.append((pkg, "📍 GPS Location"))
        
    active_ops = list(set(active_ops))
    
    if active_ops:
        print(f"{C_RED}🔴 WARNING: Active sensor access detected right now:{C_RESET}")
        for pkg, label in active_ops:
            if pkg == "com.termux":
                continue
            print(f"  • {C_BOLD}{pkg}{C_RESET} is currently using your {C_RED}{label}{C_RESET}!")
    else:
        print(f"{C_GREEN}✔ No active Microphone, Camera, or Location access detected.{C_RESET}")
    print()

def run_all_audits():
    devices = subprocess.check_output(["adb", "devices"]).decode("utf-8")
    if "127.0.0.1:5555" not in devices:
        print(f"\033[1;31m❌ ADB loopback is offline. Run adbcon first.\033[0m")
        return
        
    arg = sys.argv[1] if len(sys.argv) > 1 else "all"
    packages = get_third_party_packages()
    
    if arg == "sideloads":
        audit_sideloads(packages)
    elif arg == "hidden":
        audit_hidden(packages)
    elif arg == "permissions":
        audit_permissions(packages)
    elif arg == "system":
        audit_system_security()
    elif arg == "live":
        audit_live_access()
    else:
        print(f"\n{C_BOLD}{C_MAGENTA}============================================================{C_RESET}")
        print(f"          {C_BOLD}TER OS: SECURITY AND PRIVACY AUDIT ENGINE{C_RESET}")
        print(f"{C_BOLD}{C_MAGENTA}============================================================{C_RESET}")
        audit_sideloads(packages)
        audit_hidden(packages)
        audit_permissions(packages)
        audit_system_security()
        audit_live_access()
        print(f"\n{C_BOLD}{C_MAGENTA}============================================================{C_RESET}\n")

if __name__ == '__main__':
    run_all_audits()
EOF
}

# ── 7. APK Extractor & Exporter ──
adb-export() {
    if ! adb devices | grep -q "127.0.0.1:5555[[:space:]]*device"; then
        echo -e "${C_RED}❌ ADB loopback is offline. Run adbcon first.${C_RESET}"
        return 1
    fi

    local pkg="$1"
    if [ -z "$pkg" ]; then
        echo -n "🔍 Enter package search query (e.g. whatsapp): "
        read query
        if [ -z "$query" ]; then
            echo -e "${C_RED}❌ Query cannot be empty.${C_RESET}"
            return 1
        fi
        
        echo -e "\n📦 Matching packages:"
        local matches; matches=$(adb -s 127.0.0.1:5555 shell pm list packages -3 | grep -i "$query" | tr -d '\r' | cut -d':' -f2 | sort)
        if [ -z "$matches" ]; then
            echo -e "${C_RED}❌ No matching third-party packages found.${C_RESET}"
            return 1
        fi
        
        local options=()
        local i=1
        while read -r line; do
            options+=("$line")
            echo " [$i] $line"
            i=$((i+1))
        done <<< "$matches"
        
        echo -n "👉 Select app to export (1-$((i-1))): "
        read choice
        if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -ge "$i" ]; then
            echo -e "${C_RED}❌ Invalid choice.${C_RESET}"
            return 1
        fi
        pkg="${options[$((choice-1))]}"
    fi

    echo -e "\n🔍 Locating APK for ${C_YELLOW}$pkg${C_RESET}..."
    local paths; paths=$(adb -s 127.0.0.1:5555 shell pm path "$pkg" | tr -d '\r')
    if [ -z "$paths" ]; then
        echo -e "${C_RED}❌ Could not find package path for $pkg.${C_RESET}"
        return 1
    fi

    local base_path; base_path=$(echo "$paths" | grep "base.apk" | head -n 1 | cut -d':' -f2)
    if [ -z "$base_path" ]; then
        base_path=$(echo "$paths" | head -n 1 | cut -d':' -f2)
    fi

    local outfile="${pkg}.apk"
    echo -e "📥 Pulling APK from: ${C_DIM}$base_path${C_RESET}"
    adb -s 127.0.0.1:5555 pull "$base_path" "./$outfile"
    
    if [ $? -eq 0 ]; then
        echo -e "🎉 Successfully exported APK as: ${C_GREEN}$outfile${C_RESET} in current directory."
    else
        echo -e "${C_RED}❌ Failed to pull APK.${C_RESET}"
    fi
}

# ── 8. Boot Component Autostart Controller ──
adb-autostart() {
    if ! adb devices | grep -q "127.0.0.1:5555[[:space:]]*device"; then
        echo -e "${C_RED}❌ ADB loopback is offline. Run adbcon first.${C_RESET}"
        return 1
    fi

    echo -e "\n${C_BOLD}${C_CYAN}─── AUTOSTART RECEIVER MANAGER ───${C_RESET}"
    echo -e "${C_DIM}Scanning for apps that trigger on phone boot...${C_RESET}"
    
    python3 - << 'EOF'
import subprocess, re, sys

def run_adb(args):
    cmd = ["adb", "-s", "127.0.0.1:5555"] + args
    try:
        return subprocess.check_output(cmd, stderr=subprocess.DEVNULL).decode("utf-8", errors="ignore").replace('\r', '')
    except Exception:
        return ""

def get_third_party_packages():
    out = run_adb(["shell", "pm list packages -3"])
    packages = set()
    for line in out.splitlines():
        if line.strip().startswith("package:"):
            packages.add(line.strip().split(':')[1])
    return packages

out = run_adb(["shell", "pm query-receivers -a android.intent.action.BOOT_COMPLETED"])
third_party_names = get_third_party_packages()

receivers = []
lines = out.splitlines()
i = 0
while i < len(lines):
    line = lines[i]
    if "Receiver #" in line:
        current_pkg = None
        current_name = None
        current_enabled = None
        i += 1
        while i < len(lines) and "Receiver #" not in lines[i]:
            subline = lines[i].strip()
            if subline.startswith("name="):
                match = re.search(r"name=(\S+)", subline)
                if match:
                    current_name = match.group(1)
            elif subline.startswith("packageName="):
                match = re.search(r"packageName=(\S+)", subline)
                if match:
                    current_pkg = match.group(1)
            elif subline.startswith("enabled="):
                match = re.search(r"enabled=(true|false)", subline)
                if match:
                    current_enabled = match.group(1) == "true"
            i += 1
        if current_pkg in third_party_names and current_name:
            receivers.append({
                "package": current_pkg,
                "component": current_name,
                "enabled": current_enabled if current_enabled is not None else True
            })
        i -= 1
    i += 1

if not receivers:
    print("✔ No third-party boot receivers detected.")
    sys.exit(0)

while True:
    print(f"\n📦 Detected Boot Components (Autostart):")
    for idx, rx in enumerate(receivers, 1):
        status = "\033[1;32m[ENABLED]\033[0m" if rx["enabled"] else "\033[1;31m[DISABLED]\033[0m"
        print(f"  [{idx}] {rx['package']}\n      ↳ {rx['component']} {status}")
        
    choice = input("\n👉 Enter component number to TOGGLE state, or 'q' to quit: ").strip()
    if choice.lower() == 'q' or not choice:
        break
        
    try:
        idx = int(choice) - 1
        if idx < 0 or idx >= len(receivers):
            print("❌ Invalid number.")
            continue
    except ValueError:
        print("❌ Invalid input.")
        continue
        
    rx = receivers[idx]
    comp_path = f"{rx['package']}/{rx['component']}"
    if rx["enabled"]:
        print(f"❄️ Disabling autostart component {comp_path}...")
        res = run_adb(["shell", "pm disable", comp_path])
        if "new state" in res.lower() or "disabled" in res.lower() or not res.strip():
            rx["enabled"] = False
            print("✅ Disabled.")
        else:
            print(f"❌ Failed to disable: {res.strip()}")
    else:
        print(f"🔥 Enabling autostart component {comp_path}...")
        res = run_adb(["shell", "pm enable", comp_path])
        if "new state" in res.lower() or "enabled" in res.lower() or not res.strip():
            rx["enabled"] = True
            print("✅ Enabled.")
        else:
            print(f"❌ Failed to enable: {res.strip()}")
EOF
}

# ── 9. Standby Bucket Controller ──
adb-standby() {
    if ! adb devices | grep -q "127.0.0.1:5555[[:space:]]*device"; then
        echo -e "${C_RED}❌ ADB loopback is offline. Run adbcon first.${C_RESET}"
        return 1
    fi
    
    echo -e "\n${C_BOLD}${C_CYAN}─── APP STANDBY BUCKET TUNER ───${C_RESET}"
    echo " [1] List current standby buckets for all third-party apps"
    echo " [2] Restrict an app (Force to 'restricted' bucket for maximum battery saving)"
    echo " [3] Unrestrict an app (Set to 'active' bucket)"
    echo -n "👉 Selection (1-3): "
    read choice
    
    case "$choice" in
        1)
            echo -e "\n⏳ Gathering standby buckets... (This may take a moment)"
            python3 - << 'EOF'
import subprocess, sys
def run_adb(args):
    cmd = ["adb", "-s", "127.0.0.1:5555"] + args
    try:
        return subprocess.check_output(cmd, stderr=subprocess.DEVNULL).decode("utf-8", errors="ignore").replace('\r', '')
    except Exception:
        return ""

out_pkg = run_adb(["shell", "pm list packages -3"])
packages = []
for line in out_pkg.splitlines():
    if line.strip().startswith("package:"):
        packages.append(line.strip().split(':')[1])

buckets = {}
for pkg in sorted(packages):
    bucket_out = run_adb(["shell", "am get-standby-bucket", pkg]).strip()
    name = "unknown"
    if "10" in bucket_out or "active" in bucket_out.lower():
        name = "Active (No restrictions)"
    elif "20" in bucket_out or "working" in bucket_out.lower():
        name = "Working Set (Mild restrictions)"
    elif "30" in bucket_out or "frequent" in bucket_out.lower():
        name = "Frequent (Moderate restrictions)"
    elif "40" in bucket_out or "rare" in bucket_out.lower():
        name = "Rare (Strong restrictions)"
    elif "45" in bucket_out or "restricted" in bucket_out.lower():
        name = "\033[1;31mRestricted (Max battery saving)\033[0m"
    buckets[pkg] = name

print("\n📦 Third-Party App Standby Buckets:")
for pkg, bucket in buckets.items():
    print(f"  • \033[1m{pkg:<45}\033[0m : {bucket}")
print()
EOF
            ;;
        2)
            echo -n "👉 Enter package name to restrict: "
            read pkg
            if [ -n "$pkg" ]; then
                echo -e "⚡ Restricting package $pkg..."
                adb -s 127.0.0.1:5555 shell am set-standby-bucket "$pkg" restricted
                echo -e "✅ Package standby bucket set to ${C_RED}restricted${C_RESET}."
            fi
            ;;
        3)
            echo -n "👉 Enter package name to unrestrict: "
            read pkg
            if [ -n "$pkg" ]; then
                echo -e "🔥 Unrestricting package $pkg..."
                adb -s 127.0.0.1:5555 shell am set-standby-bucket "$pkg" active
                echo -e "✅ Package standby bucket set to ${C_GREEN}active${C_RESET}."
            fi
            ;;
        *)
            echo "❌ Invalid choice."
            ;;
    esac
    echo ""
}
