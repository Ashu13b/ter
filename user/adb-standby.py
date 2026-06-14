import subprocess, sys

def run_adb(args):
    cmd = ["adb", "-s", "127.0.0.1:5555"] + args
    try:
        proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=15)
        return proc.stdout.replace('\r', ''), proc.stderr.replace('\r', ''), proc.returncode
    except Exception as e:
        return "", str(e), -1

def main():
    devices = subprocess.check_output(["adb", "devices"]).decode("utf-8")
    if "127.0.0.1:5555" not in devices:
        print("\033[1;31m❌ ADB loopback is offline. Run adbcon first.\033[0m")
        return

    print("\n\033[1;36m─── APP STANDBY BUCKET TUNER ───\033[0m")
    print(" [1] List current standby buckets for all third-party apps")
    print(" [2] Restrict an app (Force to 'restricted' bucket for maximum battery saving)")
    print(" [3] Unrestrict an app (Set to 'active' bucket)")
    
    choice = input("👉 Selection (1-3): ").strip()
    
    if choice == "1":
        print("\n⏳ Gathering standby buckets... (This may take a moment)")
        out_pkg, _, _ = run_adb(["shell", "pm list packages -3"])
        packages = []
        for line in out_pkg.splitlines():
            if line.strip().startswith("package:"):
                packages.append(line.strip().split(':')[1])

        buckets = {}
        for pkg in sorted(packages):
            bucket_out, _, _ = run_adb(["shell", "am get-standby-bucket", pkg])
            bucket_out = bucket_out.strip()
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
        
    elif choice == "2":
        pkg = input("👉 Enter package name to restrict: ").strip()
        if pkg:
            print(f"⚡ Restricting package {pkg}...")
            stdout, stderr, code = run_adb(["shell", "am set-standby-bucket", pkg, "restricted"])
            if code == 0 and "error" not in stdout.lower() and "error" not in stderr.lower():
                print(f"✅ Package standby bucket set to \033[1;31mrestricted\033[0m.")
            else:
                err = stderr.strip() or stdout.strip() or "Unknown error"
                print(f"❌ Failed to set bucket: {err}")
                
    elif choice == "3":
        pkg = input("👉 Enter package name to unrestrict: ").strip()
        if pkg:
            print(f"🔥 Unrestricting package {pkg}...")
            stdout, stderr, code = run_adb(["shell", "am set-standby-bucket", pkg, "active"])
            if code == 0 and "error" not in stdout.lower() and "error" not in stderr.lower():
                print(f"✅ Package standby bucket set to \033[1;32mactive\033[0m.")
            else:
                err = stderr.strip() or stdout.strip() or "Unknown error"
                print(f"❌ Failed to set bucket: {err}")
                
    else:
        print("❌ Invalid choice.")

if __name__ == '__main__':
    main()
