import subprocess, re, sys

def run_adb(args):
    cmd = ["adb", "-s", "127.0.0.1:5555"] + args
    try:
        proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=15)
        return proc.stdout.replace('\r', ''), proc.stderr.replace('\r', ''), proc.returncode
    except Exception as e:
        return "", str(e), -1

def get_third_party_packages():
    out, _, _ = run_adb(["shell", "pm list packages -3"])
    packages = set()
    for line in out.splitlines():
        if line.strip().startswith("package:"):
            packages.add(line.strip().split(':')[1])
    return packages

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

def main():
    devices = subprocess.check_output(["adb", "devices"]).decode("utf-8")
    if "127.0.0.1:5555" not in devices:
        print("\033[1;31m❌ ADB loopback is offline. Run adbcon first.\033[0m")
        return

    out, _, _ = run_adb(["shell", "pm query-receivers -a android.intent.action.BOOT_COMPLETED"])
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
            category = classify_package(rx["package"])
            if category == "Safe to Disable":
                tag = "  \033[1;36m(Safe to Disable)\033[0m"
            else:
                tag = f"  \033[1;33m(Keep Enabled - {category})\033[0m"
            print(f"  [{idx}] {rx['package']}\n      ↳ {rx['component']} {status}{tag}")
            
        choice = input("\n👉 Enter component #, 'safe' to disable all safe options, or 'q' to quit: ").strip()
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
                        # Print in a dimmer color to not overwhelm the screen but show it failed
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
        if rx["enabled"]:
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
                    print("\033[1;33m   To prevent battery drain for this app, use 'adb-standby' to force it into the restricted bucket.\033[0m")
        else:
            print(f"🔥 Enabling autostart component {comp_path}...")
            stdout, stderr, code = run_adb(["shell", "pm enable", comp_path])
            if code == 0 and ("new state" in stdout.lower() or "enabled" in stdout.lower()):
                rx["enabled"] = True
                print("✅ Enabled.")
            else:
                err = stderr.strip() or stdout.strip() or "Unknown error"
                print(f"❌ Failed to enable component: {err}")

if __name__ == '__main__':
    main()
