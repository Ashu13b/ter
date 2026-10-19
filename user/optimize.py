import subprocess, sys, re, os, json, time, importlib, threading
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from adb_common import get_adb_device, run_adb as _run_adb

TASK_FILE = os.path.expanduser("~/.termux/bg_tasks.json")
LOG_DIR = os.path.expanduser("~/.termux/bg_logs")

def make_link(url, text):
    return f"\033]8;;{url}\033\\{text}\033]8;;\033\\"

def run_adb(args, device=None):
    return _run_adb(args, device=device)

def _step(label, fn):
    """Run fn() behind a single-line spinner, then leave a ✓/✗ result line.

    On a non-tty (piped) stdout the spinner is skipped and just the result is
    printed, so logs stay clean. fn() returns an rc (0 == ok)."""
    frames = "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
    tty = sys.stdout.isatty()
    if tty:
        stop = threading.Event()

        def spin():
            i = 0
            while not stop.wait(0.1):
                sys.stdout.write(f"\r\033[K  \033[1;36m{frames[i % len(frames)]}\033[0m {label}")
                sys.stdout.flush()
                i += 1

        t = threading.Thread(target=spin, daemon=True)
        t.start()
        try:
            rc = fn()
        finally:
            stop.set()
            t.join()
            sys.stdout.write("\r\033[K")
            sys.stdout.flush()
    else:
        rc = fn()
    mark = "\033[1;32m✓\033[0m" if rc == 0 else "\033[1;31m✗\033[0m"
    print(f"  {mark} {label}")
    return rc

def _adb_step(label, args):
    """Run one adb command with live progress; returns its return code."""
    def go():
        _, _, rc = run_adb(args)
        return rc
    return _step(label, go)

def ensure_adb():
    dev = get_adb_device()
    if dev:
        return dev

    # Non-interactive auto-connect. adbcon must never drop into its
    # interactive wizard here: prompts are redirected to DEVNULL, so a
    # blocking read would wedge the CLI. DEVNULL stdin cancels the wizard and
    # the timeout bounds the attempt regardless.
    def connect():
        try:
            subprocess.run(
                ["bash", "-c", "source ~/.shell.d/network/adb_connect.sh 2>/dev/null || source \"$HOME/ter/network/adb_connect.sh\"; adbcon -c"],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=20,
            )
        except subprocess.TimeoutExpired:
            pass
        return 0 if get_adb_device() else 1

    _step("Connecting to ADB device", connect)
    return get_adb_device()

def get_adb_manage():
    try:
        return importlib.import_module("adb-manage")
    except Exception:
        return None

def resolve_package(query, pkgs=None):
    adb_m = get_adb_manage()
    if not adb_m:
        return None
    if pkgs is None:
        pkgs = adb_m.get_third_party_packages()
    if query in pkgs:
        return query
    matches = [p for p in pkgs if query.lower() in p.lower()]
    if len(matches) == 1:
        return matches[0]
    elif len(matches) > 1:
        exact_seg = [p for p in matches if p.split(".")[-1].lower() == query.lower()]
        if len(exact_seg) == 1:
            return exact_seg[0]
        return matches

    # Fallback to all installed packages (including preinstalled browsers like Chrome)
    all_pkgs = adb_m.get_all_packages() if hasattr(adb_m, "get_all_packages") else []
    if query in all_pkgs:
        return query
    all_matches = [p for p in all_pkgs if query.lower() in p.lower()]
    if len(all_matches) == 1:
        return all_matches[0]
    elif len(all_matches) > 1:
        exact_seg = [p for p in all_matches if p.split(".")[-1].lower() == query.lower()]
        if len(exact_seg) == 1:
            return exact_seg[0]
        return all_matches
    return None

def allow_apps(queries):
    dev = ensure_adb()
    if not dev:
        print("\033[1;31m❌ ADB is offline. Run 'adbcon' first.\033[0m")
        return
    adb_m = get_adb_manage()
    pkgs = adb_m.get_third_party_packages() if adb_m else []
    for q in queries:
        target = resolve_package(q, pkgs)
        if not target:
            print(f"❌ Could not find installed app matching '{q}'.")
            continue
        if isinstance(target, list):
            print(f"⚠️  Multiple apps match '{q}': {', '.join(target)}. Please be more specific.")
            continue
        print(f"\n🚀 Allowing \033[1;32m{target}\033[0m to run freely in background...")
        run_adb(["shell", "dumpsys deviceidle whitelist", f"+{target}"])
        run_adb(["shell", "am set-standby-bucket", target, "active"])
        run_adb(["shell", "pm enable", target])
        print(f"  ✅ Added to Battery Optimization whitelist (Doze bypass)")
        print(f"  ✅ Standby bucket set to Active (Unrestricted)")

def restrict_apps(queries):
    dev = ensure_adb()
    if not dev:
        print("\033[1;31m❌ ADB is offline. Run 'adbcon' first.\033[0m")
        return
    adb_m = get_adb_manage()
    pkgs = adb_m.get_third_party_packages() if adb_m else []
    for q in queries:
        target = resolve_package(q, pkgs)
        if not target:
            print(f"❌ Could not find installed app matching '{q}'.")
            continue
        if isinstance(target, list):
            print(f"⚠️  Multiple apps match '{q}': {', '.join(target)}. Please be more specific.")
            continue
        print(f"\n❄️  Restricting \033[1;33m{target}\033[0m from background RAM & battery usage...")
        run_adb(["shell", "dumpsys deviceidle whitelist", f"-{target}"])
        run_adb(["shell", "am set-standby-bucket", target, "restricted"])
        print(f"  ✅ Removed from Battery Optimization whitelist")
        print(f"  ✅ Standby bucket set to Restricted (Deep Sleep when idle)")

def freeze_apps(queries):
    dev = ensure_adb()
    if not dev:
        print("\033[1;31m❌ ADB is offline. Run 'adbcon' first.\033[0m")
        return
    adb_m = get_adb_manage()
    pkgs = adb_m.get_third_party_packages() if adb_m else []
    for q in queries:
        target = resolve_package(q, pkgs)
        if not target:
            print(f"❌ Could not find installed app matching '{q}'.")
            continue
        if isinstance(target, list):
            print(f"⚠️  Multiple apps match '{q}': {', '.join(target)}. Please be more specific.")
            continue
        if adb_m:
            adb_m.freeze_app(target)
        else:
            run_adb(["shell", "pm disable-user", "--user", "0", target])

def unfreeze_apps(queries):
    dev = ensure_adb()
    if not dev:
        print("\033[1;31m❌ ADB is offline. Run 'adbcon' first.\033[0m")
        return
    adb_m = get_adb_manage()
    pkgs = adb_m.get_third_party_packages() if adb_m else []
    for q in queries:
        target = resolve_package(q, pkgs)
        if not target:
            print(f"❌ Could not find installed app matching '{q}'.")
            continue
        if isinstance(target, list):
            print(f"⚠️  Multiple apps match '{q}': {', '.join(target)}. Please be more specific.")
            continue
        if adb_m:
            adb_m.unfreeze_app(target)
        else:
            run_adb(["shell", "pm enable", target])

def run_auto_optimize():
    dev = ensure_adb()
    if not dev:
        print("\033[1;31m❌ ADB is offline. Run 'adbcon' first.\033[0m")
        return
    adb_m = get_adb_manage()
    if adb_m and hasattr(adb_m, "auto_optimize"):
        adb_m.auto_optimize()
    else:
        print("❌ adb-manage module could not be loaded.")

def list_app_states():
    dev = ensure_adb()
    if not dev:
        print("\033[1;31m❌ ADB is offline. Run 'adbcon' first.\033[0m")
        return
    adb_m = get_adb_manage()
    if not adb_m:
        print("❌ adb-manage module not found.")
        return
    packages = adb_m.get_third_party_packages()
    stdout_wl, _, _ = run_adb(["shell", "dumpsys deviceidle whitelist"])
    whitelisted_set = set()
    for line in stdout_wl.splitlines():
        parts = line.strip().split(',')
        if len(parts) >= 2:
            whitelisted_set.add(parts[1])
        elif line.strip():
            whitelisted_set.add(line.strip())

    print("\n\033[1;35m┌────────────────────────────────────────────────────────────────────────┐\033[0m")
    print("\033[1;35m│\033[0m                 📱 \033[1mTHIRD-PARTY APP BACKGROUND STATUS\033[0m                   \033[1;35m│\033[0m")
    print("\033[1;35m├────────────────────────────────────────────────────────────────────────┤\033[0m")
    print("\033[1;35m│\033[0m  \033[1mPACKAGE\033[0m                               \033[1mSTANDBY\033[0m       \033[1mBATTERY DOZE\033[0m     \033[1;35m│\033[0m")
    print("\033[1;35m├────────────────────────────────────────────────────────────────────────┤\033[0m")

    for pkg in packages:
        bucket_out, _, _ = run_adb(["shell", "am get-standby-bucket", pkg])
        bucket_out = bucket_out.strip()
        if "10" in bucket_out or "active" in bucket_out.lower() or bucket_out == "5":
            b_desc = "\033[1;32mActive\033[0m    "
        elif "20" in bucket_out or "working" in bucket_out.lower():
            b_desc = "\033[36mWorking\033[0m   "
        elif "30" in bucket_out or "frequent" in bucket_out.lower():
            b_desc = "\033[33mFrequent\033[0m  "
        elif "40" in bucket_out or "rare" in bucket_out.lower():
            b_desc = "\033[33mRare\033[0m      "
        elif "45" in bucket_out or "restricted" in bucket_out.lower():
            b_desc = "\033[1;31mRestricted\033[0m"
        else:
            b_desc = f"{bucket_out:<10}"

        is_wl = pkg in whitelisted_set or any(pkg in line for line in stdout_wl.splitlines())
        wl_desc = "\033[1;32mWhitelisted\033[0m" if is_wl else "\033[90mOptimized\033[0m  "

        pkg_short = pkg if len(pkg) <= 36 else pkg[:33] + "..."
        print(f"\033[1;35m│\033[0m  {pkg_short:<36}  {b_desc}   {wl_desc}      \033[1;35m│\033[0m")

    print("\033[1;35m└────────────────────────────────────────────────────────────────────────┘\033[0m")
    print("\n\033[1mCommands:\033[0m")
    print("  • \033[1;32moptimize allow <app>\033[0m     Allow app to run freely in background (Active + Doze Whitelist)")
    print("  • \033[1;33moptimize restrict <app>\033[0m  Put app in deep sleep when idle (Restricted)")
    print("  • \033[1;36moptimize tier\033[0m            Smart usage-based tiering (Speed compile VIP apps, Deep sleep bloat)")
    print("  • \033[1;36moptimize auto\033[0m            Auto-restrict heavy bloatware while protecting chats/tools")
    print("  • \033[1;31moptimize purge\033[0m           Kill all non-essential background processes and reclaim RAM\n")

def adaptive_tiered_optimization(dry_run=False):
    dev = ensure_adb()
    if not dev:
        print("\033[1;31m❌ ADB is offline. Run 'adbcon' first.\033[0m")
        return

    print("\n\033[1;35m┌────────────────────────────────────────────────────────────────────────┐\033[0m")
    print("\033[1;35m│\033[0m            🧠 \033[1mADAPTIVE USAGE-BASED TIER OPTIMIZATION ENGINE\033[0m           \033[1;35m│\033[0m")
    print("\033[1;35m└────────────────────────────────────────────────────────────────────────┘\033[0m")
    print("⏳ Analyzing real-world interaction frequency from Android usage engine...")

    # Query last 24h usage events
    out_usage, _, code = run_adb(["shell", "dumpsys usagestats"])
    usage_counts = {}
    if code == 0:
        for line in out_usage.splitlines():
            if "ACTIVITY_RESUMED" in line and "package=" in line:
                m = re.search(r"package=([a-zA-Z0-9._]+)", line)
                if m:
                    p = m.group(1)
                    usage_counts[p] = usage_counts.get(p, 0) + 1

    adb_m = get_adb_manage()
    pkgs = adb_m.get_third_party_packages() if adb_m else []

    protected = {
        "com.termux", "com.termux.api", "com.termux.widget",
        "com.whatsapp", "org.kaggle.platform",
        "dev.expeei.literm", "org.telegram.messenger",
        "org.openscrape.browser", "com.android.chrome",
        "com.google.android.inputmethod.latin", "org.pocketworkstation.pckeyboard"
    }

    tier_1_speed = []   # High usage: Speed-profile AOT compiled + Active Standby
    tier_2_normal = []  # Moderate usage: Working set
    tier_3_sleep = []   # Low usage / bloat: Restricted deep sleep (Bucket 45)

    for p in pkgs:
        cnt = usage_counts.get(p, 0)
        if p in protected or cnt >= 15:
            tier_1_speed.append((p, cnt))
        elif cnt >= 3:
            tier_2_normal.append((p, cnt))
        else:
            tier_3_sleep.append((p, cnt))

    # Also include essential system packages in Tier 1 if frequently used
    for p in ["com.android.chrome", "com.termux"]:
        cnt = usage_counts.get(p, 0)
        if not any(item[0] == p for item in tier_1_speed):
            tier_1_speed.append((p, cnt))

    print(f"\n\033[1;32m⚡ TIER 1: HIGH-USAGE SPEED VIP ({len(tier_1_speed)} apps)\033[0m")
    print("  Policy: Ahead-of-Time (AOT) speed compilation + Unrestricted Active Standby")
    for p, c in sorted(tier_1_speed, key=lambda x: x[1], reverse=True):
        print(f"    • {p:<38} ({c} launches in 24h)")
        if not dry_run:
            run_adb(["shell", "cmd", "package", "compile", "-m", "speed-profile", p])
            run_adb(["shell", "am", "set-standby-bucket", p, "active"])
            run_adb(["shell", "dumpsys", "deviceidle", "whitelist", f"+{p}"])

    print(f"\n\033[1;36m🔄 TIER 2: BALANCED / MODERATE ({len(tier_2_normal)} apps)\033[0m")
    print("  Policy: Working Set Standby (Bucket 20) — Normal speed, gentle idle savings")
    for p, c in sorted(tier_2_normal, key=lambda x: x[1], reverse=True):
        print(f"    • {p:<38} ({c} launches in 24h)")
        if not dry_run:
            run_adb(["shell", "am", "set-standby-bucket", p, "20"])

    print(f"\n\033[1;31m❄️  TIER 3: RARE / DEEP SLEEP ({len(tier_3_sleep)} apps)\033[0m")
    print("  Policy: Restricted Standby (Bucket 45) — 0 background CPU/RAM when idle")
    for p, c in sorted(tier_3_sleep, key=lambda x: x[1], reverse=True)[:15]:
        print(f"    • {p:<38} ({c} launches in 24h)")
        if not dry_run:
            run_adb(["shell", "am", "set-standby-bucket", p, "restricted"])
            run_adb(["shell", "cmd", "deviceidle", "whitelist", f"-{p}"])
    if len(tier_3_sleep) > 15:
        print(f"    • ...and {len(tier_3_sleep) - 15} more idle apps restricted.")
        if not dry_run:
            for p, _ in tier_3_sleep[15:]:
                run_adb(["shell", "am", "set-standby-bucket", p, "restricted"])
                run_adb(["shell", "cmd", "deviceidle", "whitelist", f"-{p}"])

    if not dry_run:
        # Sweep caches
        run_adb(["shell", "am", "kill-all"])
        print("\n\033[1;32m✅ Adaptive Tiering Applied Successfully!\033[0m")
        print("  • Primary daily tools are compiled for native maximum speed.")
        print("  • Rarely used apps are locked into deep sleep until you open them.")
    print("────────────────────────────────────────────────────────────────────────\n")

def purge_background_apps():
    dev = ensure_adb()
    if not dev:
        print("\033[1;31m❌ ADB is offline. Run 'adbcon' first.\033[0m")
        return
    adb_m = get_adb_manage()
    pkgs = set(adb_m.get_third_party_packages()) if adb_m else set()
    protected = {
        "com.termux", "com.termux.api", "com.termux.widget",
        "com.whatsapp", "org.kaggle.platform",
        "dev.expeei.literm", "org.telegram.messenger",
        "org.openscrape.browser", "com.android.chrome", "com.heytap.browser"
    }
    protected.update({"com.google.android.inputmethod.latin", "org.pocketworkstation.pckeyboard"})

    # Heavy non-essential system apps safe to kill
    killable_sys = {
        "com.android.vending",
        "com.google.android.apps.wellbeing",
        "com.google.android.googlequicksearchbox",
        "com.google.android.youtube",
        "com.google.android.gm"
    }

    # Measure initial RAM from /proc/meminfo
    def get_mem_available_kb():
        try:
            with open('/proc/meminfo', 'r') as f:
                for line in f:
                    if line.startswith('MemAvailable:'):
                        return int(line.split()[1])
        except Exception:
            pass
        return 0

    mem_before_kb = get_mem_available_kb()

    # Query running processes
    out, _, code = run_adb(["shell", "ps", "-A", "-o", "USER,PID,%CPU,%MEM,RSS,NAME"])
    if code != 0:
        print("❌ Could not query process list.")
        return

    # Track killed apps and aggregate RSS per package
    app_reclaimed_kb = {}
    proc_count_per_app = {}
    seen_killed = set()

    for line in out.splitlines()[1:]:
        parts = line.split()
        if len(parts) >= 6:
            full_name = parts[5]
            base_pkg = full_name.split(":")[0]
            rss = int(parts[4]) if parts[4].isdigit() else 0

            if (base_pkg in pkgs or base_pkg in killable_sys or full_name in killable_sys) and base_pkg not in protected:
                if base_pkg not in seen_killed:
                    if base_pkg in pkgs:
                        run_adb(["shell", "am", "force-stop", base_pkg])
                        # Lock into restricted standby bucket so Android does not wake it back up
                        run_adb(["shell", "am", "set-standby-bucket", base_pkg, "restricted"])
                        run_adb(["shell", "cmd", "deviceidle", "whitelist", f"-{base_pkg}"])
                    else:
                        run_adb(["shell", "am", "kill", base_pkg])
                    seen_killed.add(base_pkg)

                app_reclaimed_kb[base_pkg] = app_reclaimed_kb.get(base_pkg, 0) + rss
                proc_count_per_app[base_pkg] = proc_count_per_app.get(base_pkg, 0) + 1

    # Broadcast system-wide cache reclaim
    run_adb(["shell", "am", "kill-all"])

    import time
    time.sleep(0.5)
    mem_after_kb = get_mem_available_kb()
    real_delta_mb = (mem_after_kb - mem_before_kb) / 1024.0 if (mem_after_kb and mem_before_kb) else 0

    total_est_kb = sum(app_reclaimed_kb.values())
    total_est_mb = total_est_kb / 1024.0

    print("\n\033[1;35m┌────────────────────────────────────────────────────────────────────────┐\033[0m")
    print("\033[1;35m│\033[0m                       ⚡ \033[1mABSOLUTE PURGE SUMMARY\033[0m                         \033[1;35m│\033[0m")
    print("\033[1;35m├────────────────────────────────────────────────────────────────────────┤\033[0m")
    if app_reclaimed_kb:
        print(f"\033[1;35m│\033[0m  \033[1m{'Killed App / Package':<40} {'Processes':<11} {'RAM Reclaimed':<15}\033[0m \033[1;35m│\033[0m")
        print("\033[1;35m├────────────────────────────────────────────────────────────────────────┤\033[0m")
        # Sort by most RAM reclaimed
        sorted_apps = sorted(app_reclaimed_kb.items(), key=lambda x: x[1], reverse=True)
        for pkg, kb in sorted_apps:
            p_cnt = proc_count_per_app.get(pkg, 1)
            mb = kb / 1024.0
            pkg_disp = pkg if len(pkg) <= 38 else pkg[:35] + "..."
            ram_disp = f"~{mb:.1f} MB"
            print(f"\033[1;35m│\033[0m  {pkg_disp:<40} {p_cnt:<11} \033[1;32m{ram_disp:<15}\033[0m \033[1;35m│\033[0m")
    else:
        print("\033[1;35m│\033[0m  No non-essential apps were running in background.                    \033[1;35m│\033[0m")
    print("\033[1;35m├────────────────────────────────────────────────────────────────────────┤\033[0m")
    print(f"\033[1;35m│\033[0m  Total Target Apps Terminated: \033[1;32m{len(app_reclaimed_kb)}\033[0m ({sum(proc_count_per_app.values())} processes)                    \033[1;35m│\033[0m")
    print(f"\033[1;35m│\033[0m  Total Process RAM Freed:      \033[1;32m~{total_est_mb:.1f} MB\033[0m                                 \033[1;35m│\033[0m")
    if real_delta_mb > 0:
        print(f"\033[1;35m│\033[0m  Available System RAM Gain:    \033[1;32m+{real_delta_mb:.1f} MB\033[0m                                 \033[1;35m│\033[0m")
    if mem_after_kb > 0:
        print(f"\033[1;35m│\033[0m  Current Available RAM:        \033[1;36m{mem_after_kb / 1024.0 / 1024.0:.2f} GB\033[0m                                 \033[1;35m│\033[0m")
    print("\033[1;35m├────────────────────────────────────────────────────────────────────────┤\033[0m")
    print("\033[1;35m│\033[0m  🛡️  Safe: Termux, WhatsApp, Kaggle, LiteRM, Browser, Telegram, Keys    \033[1;35m│\033[0m")
    print("\033[1;35m└────────────────────────────────────────────────────────────────────────┘\033[0m\n")

def get_wake_lock_status(device=None):
    stdout, _, _ = run_adb(["shell", "dumpsys power"], device=device)
    in_wake_locks = False
    for line in stdout.splitlines():
        if "Wake Locks: size=" in line:
            in_wake_locks = True
            continue
        if in_wake_locks:
            if line.strip() == "" or line.startswith("  "):
                if "com.termux" in line:
                    return True
            else:
                in_wake_locks = False
    return False

def check_battery_optimization(device=None):
    stdout, _, _ = run_adb(["shell", "dumpsys deviceidle whitelist"], device=device)
    return "com.termux" in stdout

def check_phantom_processes(device=None):
    stdout_enabled, _, _ = run_adb(["shell", "settings get global settings_enable_monitor_phantom_procs"], device=device)
    stdout_max, _, _ = run_adb(["shell", "device_config get activity_manager max_phantom_processes"], device=device)
    
    enabled = stdout_enabled.strip().lower() != "false"
    max_val = stdout_max.strip()
    
    if not enabled:
        return True, "NO (DISABLED)"
        
    try:
        if max_val and int(max_val) >= 1000:
            return True, f"SAFE (LIMIT {max_val})"
    except ValueError:
        pass
        
    if not max_val or max_val == "null":
        return False, "EMPTY (DEFAULT 32)"
        
    return False, f"RESTRICTED ({max_val})"

def show_status(full=False):
    device = get_adb_device()
    
    if not device:
        if not full:
            print("\033[1;35m⚙ BG\033[0m  \033[1;31mADB OFFLINE\033[0m  \033[2m(Run 'adbcon' to check limits)\033[0m")
        else:
            print("\n\033[1;35m┌──────────────────────────────────────────────────────────┐\033[0m")
            print("\033[1;35m│\033[0m          ⚙️  \033[1mTERMUX BACKGROUND STABILITY ENGINE\033[0m          \033[1;35m│\033[0m")
            print("\033[1;35m├──────────────────────────────────────────────────────────┤\033[0m")
            print("\033[1;35m│\033[0m  ❌  \033[1;31mERROR: ADB is offline.\033[0m                              \033[1;35m│\033[0m")
            print("\033[1;35m│\033[0m      Cannot verify system background limits because      \033[1;35m│\033[0m")
            print("\033[1;35m│\033[0m      the local ADB service is not connected.             \033[1;35m│\033[0m")
            print("\033[1;35m│\033[0m                                                          \033[1;35m│\033[0m")
            print("\033[1;35m│\033[0m  👉  \033[1mACTION:\033[0m Run \033[1;32madbcon\033[0m to connect.                    \033[1;35m│\033[0m")
            print("\033[1;35m└──────────────────────────────────────────────────────────┘\033[0m\n")
        return

    wl = get_wake_lock_status(device=device)
    phantom_opt, phantom_raw = check_phantom_processes(device=device)
    battery_opt = check_battery_optimization(device=device)
    
    if not full:
        wl_s = "\033[1;32m✓\033[0m" if wl else "\033[1;33m✗\033[0m"
        ph_s = "\033[1;32m✓\033[0m" if phantom_opt else "\033[1;31m✗\033[0m"
        bt_s = "\033[1;32m✓\033[0m" if battery_opt else "\033[1;31m✗\033[0m"
        all_ok = wl and phantom_opt and battery_opt
        label = "\033[1;32mSTABLE\033[0m" if all_ok else "\033[1;33mCHECK\033[0m"
        print(f"\033[1;35m⚙ BG\033[0m  WakeLock:{wl_s}  Phantom:{ph_s}  Battery:{bt_s}  [{label}]  \033[2m(optimize status -f for details)\033[0m")
        if not all_ok:
            print(f"  \033[33m↳ Run \033[1moptimize fix\033[0;33m to optimize\033[0m")
        return

    wl_icon = "🟢" if wl else "🟡"
    wl_raw = "ACTIVE" if wl else "INACTIVE"
    wl_state = f"\033[1;32m{wl_raw}\033[0m" if wl else f"\033[1;33m{wl_raw}\033[0m"
    wl_padded = wl_state + (" " * (28 - len(wl_raw)))
    
    phantom_icon = "🟢" if phantom_opt else "🔴"
    phantom_state = f"\033[1;32m{phantom_raw}\033[0m" if phantom_opt else f"\033[1;31m{phantom_raw}\033[0m"
    phantom_padded = phantom_state + (" " * (28 - len(phantom_raw)))
    
    battery_icon = "🟢" if battery_opt else "🔴"
    battery_raw = "EXEMPTED" if battery_opt else "RESTRICTED"
    battery_state = f"\033[1;32m{battery_raw}\033[0m" if battery_opt else f"\033[1;31m{battery_raw}\033[0m"
    battery_padded = battery_state + (" " * (28 - len(battery_raw)))
    
    print("\n\033[1;35m┌──────────────────────────────────────────────────────────┐\033[0m")
    print("\033[1;35m│\033[0m          ⚙️  \033[1mTERMUX BACKGROUND STABILITY ENGINE\033[0m          \033[1;35m│\033[0m")
    print("\033[1;35m├──────────────────────────────────────────────────────────┤\033[0m")
    print(f"\033[1;35m│\033[0m  {wl_icon}  WakeLock             : {wl_padded}\033[1;35m│\033[0m")
    print("\033[1;35m│\033[0m      ↳ Prevents CPU from entering deep sleep             \033[1;35m│\033[0m")
    print("\033[1;35m│\033[0m                                                          \033[1;35m│\033[0m")
    print(f"\033[1;35m│\033[0m  {phantom_icon}  Phantom Process      : {phantom_padded}\033[1;35m│\033[0m")
    print("\033[1;35m│\033[0m      ↳ Monitored, but process limits are set safely      \033[1;35m│\033[0m")
    print("\033[1;35m│\033[0m                                                          \033[1;35m│\033[0m")
    print(f"\033[1;35m│\033[0m  {battery_icon}  Battery Optimization : {battery_padded}\033[1;35m│\033[0m")
    print("\033[1;35m│\033[0m      ↳ Whitelisted from App Standby & Doze               \033[1;35m│\033[0m")
    print("\033[1;35m├──────────────────────────────────────────────────────────┤\033[0m")
    
    if not phantom_opt or not battery_opt:
        msg = "  ⚠️  Some constraints are active. Run: optimize fix"
        print(f"\033[1;35m│\033[0m\033[1;33m{msg:<58}\033[0m\033[1;35m│\033[0m")
    else:
        msg = "  ✅  Termux is fully optimized for background tasks!"
        print(f"\033[1;35m│\033[0m\033[1;32m{msg:<58}\033[0m\033[1;35m│\033[0m")
        
    print("\033[1;35m└──────────────────────────────────────────────────────────┘\033[0m\n")

def show_device_info():
    dev = ensure_adb()
    if not dev:
        print("\033[1;31m❌ ADB is offline. Run 'adbcon' first.\033[0m")
        return

    model, _, _ = run_adb(["shell", "getprop", "ro.product.model"])
    android_ver, _, _ = run_adb(["shell", "getprop", "ro.build.version.release"])
    battery_info, _, _ = run_adb(["shell", "dumpsys", "battery"])

    level = "?"
    temp_c = "?"
    batt_status = "Unknown"
    for line in battery_info.splitlines():
        line_s = line.strip()
        if line_s.startswith("level:"):
            level = line_s.split(":")[1].strip()
        elif line_s.startswith("temperature:"):
            try:
                temp_raw = int(line_s.split(":")[1].strip())
                temp_c = f"{temp_raw / 10.0:.1f}"
            except Exception:
                pass
        elif line_s.startswith("status:"):
            code = line_s.split(":")[1].strip()
            batt_status = {"2": "Charging", "3": "Discharging", "4": "Not Charging", "5": "Full"}.get(code, "Unknown")

    cpu_load, _, _ = run_adb(["shell", "top", "-b", "-n", "1", "-m", "5"])
    cpu_lines = []
    header_found = False
    for line in cpu_load.splitlines():
        if "PID" in line and "USER" in line:
            header_found = True
            continue
        if header_found and line.strip():
            parts = line.split()
            if len(parts) >= 12:
                pid = parts[0]
                cpu_pct = parts[8].replace("[", "").replace("]", "")
                cmd_name = parts[11]
                cmd_short = os.path.basename(cmd_name)
                cpu_lines.append(f"{cmd_short:<26} {cpu_pct:>5}% CPU  (PID {pid})")

    print("\n\033[1;35m┌──────────────────────────────────────────────────────────┐\033[0m")
    print("\033[1;35m│\033[0m             📱 \033[1mDEVICE SYSTEM METRICS & HEALTH\033[0m            \033[1;35m│\033[0m")
    print("\033[1;35m├──────────────────────────────────────────────────────────┤\033[0m")
    print(f"\033[1;35m│\033[0m  Model   : \033[1;33m{model.strip()}\033[0m (Android {android_ver.strip()})")
    print(f"\033[1;35m│\033[0m  Battery : \033[1;32m{level}%\033[0m | Temp: \033[1;36m{temp_c}°C\033[0m | Status: {batt_status}")
    print("\033[1;35m├──────────────────────────────────────────────────────────┤\033[0m")
    print("\033[1;35m│\033[0m  \033[1mTop CPU Processes:\033[0m")
    if cpu_lines:
        for cl in cpu_lines[:5]:
            print(f"\033[1;35m│\033[0m    • {cl}")
    else:
        print("\033[1;35m│\033[0m    (No process data returned)")
    print("\033[1;35m└──────────────────────────────────────────────────────────┘\033[0m\n")

def fix_settings(include_apps=False):
    print("\n⚡ \033[1mOptimizing Termux background permissions\033[0m")
    dev = ensure_adb()
    if not dev:
        print("\033[1;31m❌ ADB is offline. Run 'adbcon' first.\033[0m")
        return

    # 1. Keep monitor on, but raise process limit ceiling to 2048
    steps = [
        ("Enable phantom-process monitor", ["shell", "settings put global settings_enable_monitor_phantom_procs true"]),
        ("Raise phantom limit → 2048", ["shell", "device_config put activity_manager max_phantom_processes 2048"]),
        # 2. Whitelist com.termux from deviceidle
        ("Whitelist Termux (Doze bypass)", ["shell", "dumpsys deviceidle whitelist +com.termux"]),
        ("Standby bucket → active", ["shell", "am set-standby-bucket com.termux active"]),
    ]
    failed = sum(1 for label, args in steps if _adb_step(label, args) != 0)

    if include_apps:
        print("\n⚡ Running app background auto-optimization...")
        run_auto_optimize()

    if failed:
        print(f"\n\033[1;33m⚠️  {failed}/{len(steps)} step(s) failed — check the ADB connection.\033[0m")
    else:
        print("\n✅ All fixes applied. Running status audit...")
    show_status()

def load_tasks():
    if not os.path.exists(TASK_FILE):
        return {}
    try:
        with open(TASK_FILE, "r") as f:
            return json.load(f)
    except Exception:
        return {}

def save_tasks(tasks):
    os.makedirs(os.path.dirname(TASK_FILE), exist_ok=True)
    with open(TASK_FILE, "w") as f:
        json.dump(tasks, f, indent=4)

def is_pid_running(pid):
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False

def clean_completed_tasks(tasks):
    updated = {}
    for name, info in tasks.items():
        if is_pid_running(info["pid"]):
            updated[name] = info
    return updated

def start_task(name, command):
    tasks = load_tasks()
    tasks = clean_completed_tasks(tasks)
    
    if name in tasks:
        print(f"❌ Error: A background task named '{name}' is already running (PID: {tasks[name]['pid']}).")
        return False

    os.makedirs(LOG_DIR, exist_ok=True)
    timestamp = time.strftime("%Y%m%d_%H%M%S")
    log_file_name = f"{name}_{timestamp}.log"
    log_path = os.path.join(LOG_DIR, log_file_name)
    
    shell_cmd = f"termux-wake-lock && {command} ; code=$? ; termux-wake-unlock"
    
    try:
        log_f = open(log_path, "w")
        proc = subprocess.Popen(
            ["sh", "-c", shell_cmd],
            stdout=log_f,
            stderr=log_f,
            stdin=subprocess.DEVNULL,
            start_new_session=True
        )
        
        tasks[name] = {
            "pid": proc.pid,
            "command": command,
            "log": log_path,
            "started": time.strftime("%Y-%m-%d %H:%M:%S")
        }
        save_tasks(tasks)
        
        print(f"🚀 Started background task: \033[1;36m{name}\033[0m")
        print(f"  • PID: {proc.pid}")
        print(f"  • Log File: {log_path}")
        return True
    except Exception as e:
        print(f"❌ Failed to spawn task: {str(e)}")
        return False

def list_tasks():
    tasks = load_tasks()
    running = {}
    
    task_keys = [k for k, v in tasks.items() if is_pid_running(v["pid"])]
    
    print("\n\033[1;35m┌──────────────────────────────────────────────────────────────────────────┐\033[0m")
    print("\033[1;35m│\033[0m                       📦 \033[1mACTIVE BACKGROUND TASKS\033[0m                          \033[1;35m│\033[0m")
    print("\033[1;35m├──────────────────────────────────────────────────────────────────────────┤\033[0m")
    
    for idx, name in enumerate(task_keys, 1):
        info = tasks[name]
        running[name] = info
        print(f"\033[1;35m│\033[0m  [{idx}] \033[1;36m{name:<16}\033[0m | PID: {info['pid']:<6} | Started: {info['started']:<19}    \033[1;35m│\033[0m")
        
        cmd_str = info['command']
        if len(cmd_str) > 60:
            cmd_str = cmd_str[:57] + "..."
        print(f"\033[1;35m│\033[0m    ↳ Cmd: {cmd_str:<63}\033[1;35m│\033[0m")
        
        log_str = info['log']
        if len(log_str) > 60:
            log_str = "..." + log_str[-57:]
        print(f"\033[1;35m│\033[0m    ↳ Log: {log_str:<63}\033[1;35m│\033[0m")
        
        if idx < len(task_keys):
            print("\033[1;35m├──────────────────────────────────────────────────────────────────────────┤\033[0m")
            
    if not task_keys:
        msg = "  No active background tasks running"
        print(f"\033[1;35m│\033[0m{msg:<74}\033[1;35m│\033[0m")
        
    print("\033[1;35m└──────────────────────────────────────────────────────────────────────────┘\033[0m\n")
    
    save_tasks(running)

def stop_task(name):
    tasks = load_tasks()
    if name not in tasks or not is_pid_running(tasks[name]["pid"]):
        print(f"❌ Task '{name}' is not running.")
        return False
    
    pid = tasks[name]["pid"]
    print(f"🛑 Stopping task '{name}' (Killing PID {pid})...")
    try:
        os.killpg(os.getpgid(pid), 15)
        print("✅ Task stopped.")
    except Exception:
        try:
            os.kill(pid, 15)
            print("✅ Task stopped.")
        except Exception as e:
            print(f"❌ Failed to kill task: {str(e)}")
            
    tasks.pop(name, None)
    save_tasks(tasks)
    return True

def print_help():
    print("\033[1;36mTERMUX BACKGROUND STABILITY & APP OPTIMIZATION MANAGER\033[0m")
    print()
    print("\033[1mSystem Stability & Metrics:\033[0m")
    print("  optimize status             Quick audit (compact one-liner)")
    print("  optimize status -f          Full detailed audit with descriptions")
    print("  optimize info               Show device metrics, battery %, temperature, & top CPU")
    print("  optimize fix                Optimize via ADB (phantom limit → 2048, battery whitelist)")
    print("  optimize fix --apps         Fix system limits AND auto-optimize background apps")
    print()
    print("\033[1mApp Background & Battery Management:\033[0m")
    print("  optimize allow <app ...>    Allow app(s) to run freely in background (Active + Doze Whitelist)")
    print("  optimize restrict <app ...> Restrict app(s) to deep sleep to save RAM & battery")
    print("  optimize freeze <app>       Freeze/disable bloatware completely (0 RAM/battery)")
    print("  optimize unfreeze <app>     Unfreeze/enable a previously frozen app")
    print("  optimize tier               Smart usage-based tiering (Speed compile VIP apps, Deep sleep bloat)")
    print("  optimize auto               Auto-restrict heavy background apps (shopping, food, etc.)")
    print("  optimize purge              Kill all non-essential background processes & reclaim RAM")
    print("  optimize apps               List installed third-party apps and background status")
    print()
    print("\033[1mBackground Tasks:\033[0m")
    print("  optimize run <name> <cmd>   Launch command in background with WakeLock & logging")
    print("  optimize list               List all active background tasks")
    print("  optimize stop <name>        Terminate a running background task")
    print("  optimize log <name>         Show log path and tail last 20 lines")
    print()
    print("\033[1mExamples:\033[0m")
    print("  optimize tier")
    print("  optimize allow whatsapp telegram obsidian kaggle")
    print("  optimize restrict swiggy flipkart zomato")
    print("  optimize purge")
    print("  optimize info")
    print("  optimize auto")
    print("  optimize run myserver \"python3 -m http.server 8080\"")
    print()

def main():
    args = sys.argv[1:]
    if not args or args[0] in ["-h", "--help", "help"]:
        print_help()
        sys.exit(0)
        
    cmd = args[0]
    if cmd == "status":
        full = len(args) > 1 and args[1] in ["-f", "--full"]
        show_status(full=full)
    elif cmd in ["info", "sysinfo", "battery", "temp"]:
        show_device_info()
    elif cmd == "fix":
        include_apps = len(args) > 1 and args[1] in ["-a", "--apps"]
        fix_settings(include_apps=include_apps)
    elif cmd in ["tier", "tiered", "profile", "adaptive"]:
        dry_run = len(args) > 1 and args[1] in ["-n", "--dry-run", "dry-run"]
        adaptive_tiered_optimization(dry_run=dry_run)
    elif cmd in ["purge", "kill-bg", "clean-bg"]:
        purge_background_apps()
    elif cmd in ["allow", "keep"]:
        if len(args) < 2:
            print("❌ Error: Missing app name(s).")
            print("Usage: optimize allow <app1> [app2 ...]")
            sys.exit(1)
        allow_apps(args[1:])
    elif cmd == "restrict":
        if len(args) < 2:
            print("❌ Error: Missing app name(s).")
            print("Usage: optimize restrict <app1> [app2 ...]")
            sys.exit(1)
        restrict_apps(args[1:])
    elif cmd == "freeze":
        if len(args) < 2:
            print("❌ Error: Missing app name(s).")
            print("Usage: optimize freeze <app>")
            sys.exit(1)
        freeze_apps(args[1:])
    elif cmd == "unfreeze":
        if len(args) < 2:
            print("❌ Error: Missing app name(s).")
            print("Usage: optimize unfreeze <app>")
            sys.exit(1)
        unfreeze_apps(args[1:])
    elif cmd == "auto":
        if len(args) > 1 and args[1] in ["--tier", "--tiered", "tier", "tiered"]:
            dry_run = len(args) > 2 and args[2] in ["-n", "--dry-run", "dry-run"]
            adaptive_tiered_optimization(dry_run=dry_run)
        else:
            run_auto_optimize()
    elif cmd == "apps":
        if len(args) > 1:
            sub = args[1]
            if sub in ["tier", "tiered", "profile", "adaptive"]:
                dry_run = len(args) > 2 and args[2] in ["-n", "--dry-run", "dry-run"]
                adaptive_tiered_optimization(dry_run=dry_run)
            elif sub == "auto":
                run_auto_optimize()
            elif sub in ["allow", "keep"]:
                allow_apps(args[2:])
            elif sub == "restrict":
                restrict_apps(args[2:])
            elif sub == "freeze":
                freeze_apps(args[2:])
            elif sub == "unfreeze":
                unfreeze_apps(args[2:])
            else:
                print(f"❌ Unknown sub-command: {sub}")
                print("Usage: optimize apps [tier|auto|allow|restrict|freeze|unfreeze]")
        else:
            list_app_states()
    elif cmd == "run":
        if len(args) < 3:
            print("❌ Error: Missing task name or command.")
            print("Usage: optimize run <name> \"<command>\"")
            sys.exit(1)
        start_task(args[1], args[2])
    elif cmd == "list":
        list_tasks()
    elif cmd == "stop":
        if len(args) < 2:
            print("❌ Error: Missing task name.")
            sys.exit(1)
        stop_task(args[1])
    elif cmd == "log":
        if len(args) < 2:
            print("❌ Error: Missing task name.")
            sys.exit(1)
        name = args[1]
        tasks = load_tasks()
        if name in tasks:
            print(f"Log path: {tasks[name]['log']}")
            print(f"Tail logs:")
            subprocess.run(["tail", "-n", "20", tasks[name]['log']])
        else:
            if os.path.exists(LOG_DIR):
                matches = sorted([f for f in os.listdir(LOG_DIR) if f.startswith(name)])
                if matches:
                    log_path = os.path.join(LOG_DIR, matches[-1])
                    print(f"Log path: {log_path}")
                    print(f"Tail logs:")
                    subprocess.run(["tail", "-n", "20", log_path])
                    return
            print(f"❌ No logs found for task '{name}'.")
    else:
        print(f"❌ Unknown command: {cmd}")
        print_help()
        sys.exit(1)

if __name__ == '__main__':
    main()
