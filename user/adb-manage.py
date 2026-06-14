import subprocess, sys, re, os

def make_link(url, text):
    return f"\033]8;;{url}\033\\{text}\033]8;;\033\\"

def run_adb(args):
    cmd = ["adb", "-s", "127.0.0.1:5555"] + args
    try:
        proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20)
        return proc.stdout.replace('\r', ''), proc.stderr.replace('\r', ''), proc.returncode
    except Exception as e:
        return "", str(e), -1

def get_third_party_packages():
    out, _, _ = run_adb(["shell", "pm list packages -3"])
    packages = []
    for line in out.splitlines():
        if line.strip().startswith("package:"):
            packages.append(line.strip().split(':')[1])
    return sorted(packages)

def freeze_app(pkg):
    print(f"❄️ Freezing package {pkg}...")
    stdout, stderr, code = run_adb(["shell", "pm disable-user", "--user", "0", pkg])
    if code == 0 and ("disabled" in stdout.lower() or "disabled" in stderr.lower() or not stdout.strip()):
        print(f"✅ Package disabled. It will not run or consume battery.")
        return True
    else:
        err = stderr.strip() or stdout.strip() or "Unknown error"
        print(f"❌ Failed to freeze package: {err}")
        return False

def unfreeze_app(pkg):
    print(f"🔥 Unfreezing package {pkg}...")
    stdout, stderr, code = run_adb(["shell", "pm enable", pkg])
    if code == 0 and ("enabled" in stdout.lower() or not stdout.strip()):
        print(f"✅ Package enabled.")
        return True
    else:
        err = stderr.strip() or stdout.strip() or "Unknown error"
        print(f"❌ Failed to unfreeze package: {err}")
        return False

def set_standby(pkg, bucket):
    category = classify_package(pkg)
    if bucket == "restricted" and category != "Safe to Disable":
        print(f"\033[1;33m⚠️ Note: {pkg} is classified as '{category}'. Background limits may affect performance.\033[0m")
        
    print(f"⚡ Setting standby bucket for {pkg} to {bucket}...")
    stdout, stderr, code = run_adb(["shell", "am set-standby-bucket", pkg, bucket])
    if code == 0 and "error" not in stdout.lower() and "error" not in stderr.lower():
        color = "\033[1;31m" if bucket == "restricted" else "\033[1;32m"
        print(f"✅ Package standby bucket set to {color}{bucket}\033[0m.")
        return True
    else:
        err = stderr.strip() or stdout.strip() or "Unknown error"
        print(f"❌ Failed to set bucket: {err}")
        return False

def export_apk(pkg):
    print(f"🔍 Locating APK for {pkg}...")
    paths, stderr, code = run_adb(["shell", "pm path", pkg])
    if code != 0 or not paths.strip():
        print(f"❌ Could not find package path for {pkg}.")
        return False

    base_path = None
    for line in paths.splitlines():
        if "base.apk" in line:
            base_path = line.strip().split(':')[1]
            break
    if not base_path:
        base_path = paths.splitlines()[0].strip().split(':')[1]

    outfile = f"{pkg}.apk"
    print(f"📥 Pulling APK from: {base_path}...")
    
    # We run adb pull directly
    cmd = ["adb", "-s", "127.0.0.1:5555", "pull", base_path, f"./{outfile}"]
    try:
        proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        if proc.returncode == 0:
            outfile_abs = os.path.abspath(outfile)
            clickable_outfile = make_link(f"file://{outfile_abs}", outfile)
            print(f"🎉 Successfully exported APK as: \033[1;32m{clickable_outfile}\033[0m in current directory.")
            return True
        else:
            print(f"❌ Failed to pull APK: {proc.stderr.strip()}")
            return False
    except Exception as e:
        print(f"❌ Failed to pull APK: {str(e)}")
        return False

# Standby Buckets Manager
def standby_menu():
    while True:
        print("\n⏳ Gathering standby states... (This may take a moment)")
        packages = get_third_party_packages()
        app_list = []
        for pkg in packages:
            bucket_out, _, _ = run_adb(["shell", "am get-standby-bucket", pkg])
            bucket_out = bucket_out.strip()
            
            # Categorize bucket
            state_code = "unknown"
            state_desc = "Unknown"
            if "10" in bucket_out or "active" in bucket_out.lower():
                state_code = "active"
                state_desc = "\033[1;32mActive (Unrestricted)\033[0m"
            elif "20" in bucket_out or "working" in bucket_out.lower():
                state_code = "working"
                state_desc = "Working Set (Mild)"
            elif "30" in bucket_out or "frequent" in bucket_out.lower():
                state_code = "frequent"
                state_desc = "Frequent (Moderate)"
            elif "40" in bucket_out or "rare" in bucket_out.lower():
                state_code = "rare"
                state_desc = "Rare (Strong limit)"
            elif "45" in bucket_out or "restricted" in bucket_out.lower():
                state_code = "restricted"
                state_desc = "\033[1;31mRestricted (Max saving)\033[0m"
                
            category = classify_package(pkg)
            app_list.append({
                "package": pkg,
                "state_code": state_code,
                "state_desc": state_desc,
                "category": category
            })
            
        print("\n\033[1;36m─── APP STANDBY BUCKET TUNER ───\033[0m")
        for idx, app in enumerate(app_list, 1):
            if app["category"] == "Safe to Disable":
                tag = "  \033[1;36m(Safe to Restrict)\033[0m"
            else:
                tag = f"  \033[1;33m(Keep Active - {app['category']})\033[0m"
            print(f"  [{idx}] {app['package']}\n      ↳ Standby: {app['state_desc']}{tag}")
            
        print("\nOptions:")
        print("  • Enter # to toggle standby state (Active ⟷ Restricted) for an app")
        print("  • Type 'bulk' to restrict all 'Safe to Restrict' apps at once")
        print("  • Type 'b' to return to main menu")
        
        choice = input("\n👉 Choice: ").strip()
        if choice.lower() == 'b' or not choice:
            break
        
        if choice.lower() == 'bulk':
            print("\n⚡ Bulk restricting all safe applications...")
            restricted_count = 0
            for app in app_list:
                if app["category"] == "Safe to Disable" and app["state_code"] != "restricted":
                    print(f"  ❄️ Restricting {app['package']}...")
                    if set_standby(app["package"], "restricted"):
                        restricted_count += 1
            print(f"\n✅ Done! Restricted {restricted_count} safe apps.")
            continue
            
        try:
            idx = int(choice) - 1
            if 0 <= idx < len(app_list):
                app = app_list[idx]
                if app["state_code"] == "restricted":
                    set_standby(app["package"], "active")
                else:
                    if app["category"] != "Safe to Disable":
                        print(f"\033[1;33m⚠️ WARNING: This app is classified as '{app['category']}'.\033[0m")
                        print("  Restricting it might delay push notifications or cause background sync issues.")
                        confirm = input("👉 Are you sure you want to restrict it? (y/N): ").strip().lower()
                        if confirm != 'y':
                            print("❌ Action cancelled.")
                            continue
                    set_standby(app["package"], "restricted")
            else:
                print("❌ Invalid number.")
        except ValueError:
            print("❌ Invalid input.")

# Autostart Sub-menu
CRITICAL_PATTERNS = [
    r"whatsapp", r"telegram", r"messenger", r"discord", r"signal", r"skype",
    r"keyboard", r"inputmethod", r"ime", r"gboard", r"swiftkey",
    r"watch", r"wear", r"fitbit", r"garmin", r"tuya", r"smartlife", r"miband",
    r"clock", r"alarm", r"calendar",
    r"launcher",
    r"termux"
]

def classify_package(pkg):
    for pattern in CRITICAL_PATTERNS:
        if re.search(pattern, pkg.lower()):
            if any(p in pattern for p in ["whatsapp", "telegram", "messenger", "discord", "signal"]):
                return "Chat/Messaging"
            elif any(p in pattern for p in ["keyboard", "inputmethod", "ime", "gboard", "swiftkey"]):
                return "Keyboard/IME"
            elif any(p in pattern for p in ["watch", "wear", "fitbit", "garmin", "tuya", "smartlife"]):
                return "IoT/Wearable"
            elif any(p in pattern for p in ["clock", "alarm"]):
                return "Alarm/Clock"
            elif "calendar" in pattern:
                return "Calendar"
            elif "launcher" in pattern:
                return "Launcher"
            return "System/Core Utility"
    return "Safe to Disable"

def autostart_menu():
    while True:
        print("\n⏳ Scanning boot autostart receivers... (This may take a moment)")
        out, _, _ = run_adb(["shell", "pm query-receivers -a android.intent.action.BOOT_COMPLETED"])
        third_party_names = set(get_third_party_packages())

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
                    if "ApplicationInfo:" in lines[i]:
                        while i < len(lines) and "Receiver #" not in lines[i]:
                            i += 1
                        break
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
            break

        print(f"\n📦 Detected Boot Components (Autostart):")
        for idx, rx in enumerate(receivers, 1):
            status = "\033[1;32m[ENABLED]\033[0m" if rx["enabled"] else "\033[1;31m[DISABLED]\033[0m"
            category = classify_package(rx["package"])
            if category == "Safe to Disable":
                tag = "  \033[1;36m(Safe to Disable)\033[0m"
            else:
                tag = f"  \033[1;33m(Keep Enabled - {category})\033[0m"
            print(f"  [{idx}] {rx['package']}\n      ↳ {rx['component']} {status}{tag}")
            
        choice = input("\n👉 Enter component #, 'safe' to disable all safe options, or 'q' to return: ").strip()
        if choice.lower() == 'q' or not choice:
            break
            
        if choice.lower() == 'safe':
            print("\n⚡ Bulk disabling all safe autostart components...")
            disabled_count = 0
            failed_count = 0
            for rx in receivers:
                category = classify_package(rx["package"])
                if category == "Safe to Disable" and rx["enabled"]:
                    comp_path = f"{rx['package']}/{rx['component']}"
                    print(f"  ❄️ Disabling {comp_path}...")
                    stdout, stderr, code = run_adb(["shell", "pm disable", comp_path])
                    if code == 0 and ("new state" in stdout.lower() or "disabled" in stdout.lower()):
                        rx["enabled"] = False
                        disabled_count += 1
                    else:
                        failed_count += 1
                        err = stderr.strip() or stdout.strip() or "Unknown error"
                        print(f"    \033[2m❌ Failed: {err}\033[0m")
            print(f"\n✅ Done! Bulk disabled {disabled_count} components. ({failed_count} failed due to system/OEM permissions)")
            continue
            
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
        category = classify_package(rx["package"])
        if rx["enabled"]:
            if category != "Safe to Disable":
                print(f"\033[1;33m⚠️ WARNING: This app is classified as '{category}'.\033[0m")
                print("  Disabling its autostart receiver may prevent it from starting up or receiving boot messages.")
                confirm = input("👉 Are you sure you want to disable it? (y/N): ").strip().lower()
                if confirm != 'y':
                    print("❌ Action cancelled.")
                    continue
            print(f"❄️ Disabling autostart component {comp_path}...")
            stdout, stderr, code = run_adb(["shell", "pm disable", comp_path])
            if code == 0 and ("new state" in stdout.lower() or "disabled" in stdout.lower()):
                rx["enabled"] = False
                print("✅ Disabled.")
            else:
                err = stderr.strip() or stdout.strip() or "Unknown error"
                print(f"❌ Failed to disable component: {err}")
                if "securityexception" in err.lower():
                    print("\033[1;33m💡 Hint: Modern Android versions restrict non-root ADB shell from disabling individual components.\033[0m")
                    print("\033[1;33m   To prevent battery drain for this app, use 'Standby Tuner' to force it into the restricted bucket.\033[0m")
        else:
            print(f"🔥 Enabling autostart component {comp_path}...")
            stdout, stderr, code = run_adb(["shell", "pm enable", comp_path])
            if code == 0 and ("new state" in stdout.lower() or "enabled" in stdout.lower()):
                rx["enabled"] = True
                print("✅ Enabled.")
            else:
                err = stderr.strip() or stdout.strip() or "Unknown error"
                print(f"❌ Failed to enable component: {err}")

# Search package function
def search_package_interactive(msg="Enter package search query (e.g. whatsapp): "):
    query = input(f"🔍 {msg}").strip()
    if not query:
        print("❌ Query cannot be empty.")
        return None
    
    packages = get_third_party_packages()
    matches = [p for p in packages if query.lower() in p.lower()]
    
    if not matches:
        print("❌ No matching third-party packages found.")
        return None
    
    print("\n📦 Matching packages:")
    for idx, pkg in enumerate(matches, 1):
        print(f" [{idx}] {pkg}")
    
    choice = input(f"👉 Select app (1-{len(matches)}): ").strip()
    try:
        val = int(choice) - 1
        if 0 <= val < len(matches):
            return matches[val]
    except ValueError:
        pass
    print("❌ Invalid selection.")
    return None

def auto_optimize():
    print("\n\033[1;35m⚡ RUNNING SAFE AUTO-OPTIMIZATION ⚡\033[0m")
    print("------------------------------------------------------------")
    
    # 1. Standby bucket optimization
    print("⏳ Optimizing Standby Buckets...")
    packages = get_third_party_packages()
    restricted_count = 0
    for pkg in packages:
        category = classify_package(pkg)
        if category == "Safe to Disable":
            bucket_out, _, _ = run_adb(["shell", "am get-standby-bucket", pkg])
            bucket_out = bucket_out.strip()
            if "45" not in bucket_out and "restricted" not in bucket_out.lower():
                print(f"  ❄️ Restricting standby for: {pkg}...")
                if set_standby(pkg, "restricted"):
                    restricted_count += 1
                    
    # 2. Autostart receiver optimization
    print("\n⏳ Optimizing Boot Autostart Receivers...")
    out, _, _ = run_adb(["shell", "pm query-receivers -a android.intent.action.BOOT_COMPLETED"])
    third_party_names = set(packages)
    
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
                if "ApplicationInfo:" in lines[i]:
                    while i < len(lines) and "Receiver #" not in lines[i]:
                        i += 1
                    break
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
        
    disabled_count = 0
    failed_count = 0
    for rx in receivers:
        category = classify_package(rx["package"])
        if category == "Safe to Disable" and rx["enabled"]:
            comp_path = f"{rx['package']}/{rx['component']}"
            print(f"  ❄️ Disabling autostart component: {comp_path}...")
            stdout, stderr, code = run_adb(["shell", "pm disable", comp_path])
            if code == 0 and ("new state" in stdout.lower() or "disabled" in stdout.lower()):
                disabled_count += 1
            else:
                failed_count += 1
                
    print("\n------------------------------------------------------------")
    print(f"\033[1;32m✅ Safe Optimization Complete!\033[0m")
    print(f"  • Restricted standby buckets for {restricted_count} packages.")
    print(f"  • Disabled autostart receivers for {disabled_count} components.")
    if failed_count > 0:
        print(f"  • {failed_count} components could not be disabled due to Android Security restrictions (Safe, as we restricted their standby buckets instead).")
    print("------------------------------------------------------------\n")

# Main Dashboard menu
def dashboard():
    while True:
        print("\n\033[1;35m============================================================\033[0m")
        print("          \033[1mTER OS: ADB APP MANAGER & OPTIMIZER\033[0m")
        print("\033[1;35m============================================================\033[0m")
        print(" [1] Auto-Optimize (Safe Battery Saving)")
        print(" [2] Freeze App (Disable package completely)")
        print(" [3] Unfreeze App (Re-enable package)")
        print(" [4] Standby Tuner (Manage standby buckets)")
        print(" [5] Autostart Controller (Manage boot-start receivers)")
        print(" [6] Export App APK (Extract base APK file)")
        print(" [7] List Installed Third-Party Apps")
        print(" [q] Quit")
        choice = input("\n👉 Selection (1-7 or q): ").strip()
        
        if choice.lower() == 'q' or not choice:
            break
        elif choice == "1":
            auto_optimize()
        elif choice == "2":
            pkg = search_package_interactive("Enter package to FREEZE: ")
            if pkg:
                freeze_app(pkg)
        elif choice == "3":
            # For unfreeze, we list all disabled apps
            print("\n⏳ Finding frozen apps...")
            out, _, _ = run_adb(["shell", "pm list packages -d -3"])
            frozen = []
            for line in out.splitlines():
                if line.strip().startswith("package:"):
                    frozen.append(line.strip().split(':')[1])
            
            if not frozen:
                print("✔ No frozen third-party packages found.")
                continue
            
            print("\n❄️ Frozen packages:")
            for idx, pkg in enumerate(frozen, 1):
                print(f" [{idx}] {pkg}")
            
            sel = input(f"👉 Select package to UNFREEZE (1-{len(frozen)}): ").strip()
            try:
                val = int(sel) - 1
                if 0 <= val < len(frozen):
                    unfreeze_app(frozen[val])
                    continue
            except ValueError:
                pass
            print("❌ Invalid selection.")
        elif choice == "4":
            standby_menu()
        elif choice == "5":
            autostart_menu()
        elif choice == "6":
            pkg = search_package_interactive("Enter package to EXPORT: ")
            if pkg:
                export_apk(pkg)
        elif choice == "7":
            print("\n📦 Installed Third-Party Packages:")
            packages = get_third_party_packages()
            for pkg in packages:
                print(f"  • {pkg}")
            print()
        else:
            print("❌ Invalid choice.")

def print_help():
    print("\033[1mTER OS: Consolidated ADB Management Utility\033[0m")
    print("Usage:")
    print("  adb-manage                  Open interactive dashboard menu")
    print("  adb-manage -o/--optimize     Run safe auto-optimization (autostart & standby)")
    print("  adb-manage -f/--freeze <pkg>  Disable/Freeze an app completely")
    print("  adb-manage -u/--unfreeze <pkg> Re-enable/Unfreeze an app")
    print("  adb-manage -s/--standby <pkg> [restricted|active]  Tune app standby bucket")
    print("  adb-manage -e/--export <pkg>  Extract and pull base APK file")
    print("  adb-manage -a/--autostart    Open boot components manager directly")
    print("  adb-manage -h/--help         Show this help information")
    print()

def cli_main():
    args = sys.argv[1:]
    if args and args[0] in ["-h", "--help"]:
        print_help()
        sys.exit(0)

    devices = subprocess.check_output(["adb", "devices"]).decode("utf-8")
    if "127.0.0.1:5555" not in devices:
        print("\033[1;31m❌ ADB loopback is offline. Run adbcon first.\033[0m")
        sys.exit(1)

    if not args:
        dashboard()
        return

    cmd = args[0]
    if cmd in ["-o", "--optimize"]:
        auto_optimize()
    elif cmd in ["-f", "--freeze"]:
        if len(args) < 2:
            print("❌ Error: Missing package name.")
            sys.exit(1)
        freeze_app(args[1])
    elif cmd in ["-u", "--unfreeze"]:
        if len(args) < 2:
            print("❌ Error: Missing package name.")
            sys.exit(1)
        unfreeze_app(args[1])
    elif cmd in ["-s", "--standby"]:
        if len(args) < 2:
            print("❌ Error: Missing package name.")
            sys.exit(1)
        bucket = args[2] if len(args) > 2 else "restricted"
        set_standby(args[1], bucket)
    elif cmd in ["-e", "--export"]:
        if len(args) < 2:
            print("❌ Error: Missing package name.")
            sys.exit(1)
        export_apk(args[1])
    elif cmd in ["-a", "--autostart"]:
        autostart_menu()
    else:
        print(f"❌ Unknown option: {cmd}")
        print_help()
        sys.exit(1)

if __name__ == '__main__':
    cli_main()
