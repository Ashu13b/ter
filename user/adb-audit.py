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

def print_help():
    print(f"{C_BOLD}{C_CYAN}─── TER OS: ADB-Powered Security Audit ───{C_RESET}")
    print("Usage: adb-audit [option]\n")
    print("Options:")
    print("  -a, --all          Run full device security & privacy audit")
    print("  -s, --sideloads    Scan for sideloaded/ADB-installed apps")
    print("  -d, --hidden       Scan for running iconless background apps")
    print("  -p, --permissions  Scan granted dangerous privacy permissions (categorized & chunked)")
    print("  -y, --system       Scan active Device Administrators & Accessibility Services")
    print("  -i, --live         Scan active Microphone, Camera, or Location access right now")
    print("  -h, --help         Show this help information")
    print()

def run_all_audits():
    arg = sys.argv[1] if len(sys.argv) > 1 else "all"
    if arg in ["-h", "--help", "help"]:
        print_help()
        sys.exit(0)

    if arg in ["-s", "--sideloads"]:
        arg = "sideloads"
    elif arg in ["-d", "--hidden"]:
        arg = "hidden"
    elif arg in ["-p", "--permissions"]:
        arg = "permissions"
    elif arg in ["-y", "--system"]:
        arg = "system"
    elif arg in ["-i", "--live"]:
        arg = "live"
    elif arg in ["-a", "--all"]:
        arg = "all"

    devices = subprocess.check_output(["adb", "devices"]).decode("utf-8")
    if "127.0.0.1:5555" not in devices:
        print(f"\033[1;31m❌ ADB loopback is offline. Run adbcon first.\033[0m")
        sys.exit(1)
        
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
    elif arg == "all":
        print(f"\n{C_BOLD}{C_MAGENTA}============================================================{C_RESET}")
        print(f"          {C_BOLD}TER OS: SECURITY AND PRIVACY AUDIT ENGINE{C_RESET}")
        print(f"{C_BOLD}{C_MAGENTA}============================================================{C_RESET}")
        audit_sideloads(packages)
        audit_hidden(packages)
        audit_permissions(packages)
        audit_system_security()
        audit_live_access()
        print(f"\n{C_BOLD}{C_MAGENTA}============================================================{C_RESET}\n")
    else:
        print(f"❌ Unknown option: {arg}")
        print_help()
        sys.exit(1)

if __name__ == '__main__':
    run_all_audits()
