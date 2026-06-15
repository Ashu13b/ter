import subprocess, sys, re, os, json, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from adb_common import get_adb_device, run_adb as _run_adb

TASK_FILE = os.path.expanduser("~/.termux/bg_tasks.json")
LOG_DIR = os.path.expanduser("~/.termux/bg_logs")

def make_link(url, text):
    return f"\033]8;;{url}\033\\{text}\033]8;;\033\\"

def run_adb(args, device=None):
    return _run_adb(args, device=device)

def get_wake_lock_status(device=None):
    # Query dumpsys power to see if com.termux holds a wake lock
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
    
    # If the monitor is disabled entirely, it is optimized but has no safety restrictions
    if not enabled:
        return True, "NO (DISABLED)"
        
    # If it is enabled but the ceiling is high (>= 1000), it is optimized with safety headroom
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
        # Compact one-line startup summary
        wl_s = "\033[1;32m✓\033[0m" if wl else "\033[1;33m✗\033[0m"
        ph_s = "\033[1;32m✓\033[0m" if phantom_opt else "\033[1;31m✗\033[0m"
        bt_s = "\033[1;32m✓\033[0m" if battery_opt else "\033[1;31m✗\033[0m"
        all_ok = wl and phantom_opt and battery_opt
        label = "\033[1;32mSTABLE\033[0m" if all_ok else "\033[1;33mCHECK\033[0m"
        print(f"\033[1;35m⚙ BG\033[0m  WakeLock:{wl_s}  Phantom:{ph_s}  Battery:{bt_s}  [{label}]  \033[2m(optimize status -f for details)\033[0m")
        if not all_ok:
            print(f"  \033[33m↳ Run \033[1moptimize fix\033[0;33m to optimize\033[0m")
        return

    # Full verbose box
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

def fix_settings():
    print("\n⚡ Optimizing Termux background permissions...")
    
    # 1. Keep monitor on, but raise process limit ceiling to 2048 to prevent runaways while allowing heavy Termux usage
    print("  🛠️ Setting Phantom Process limit to 2048...")
    run_adb(["shell", "settings put global settings_enable_monitor_phantom_procs true"])
    run_adb(["shell", "device_config put activity_manager max_phantom_processes 2048"])
    
    # 2. Whitelist com.termux from deviceidle
    print("  🛠️ Whitelisting Termux from battery optimization...")
    run_adb(["shell", "dumpsys deviceidle whitelist +com.termux"])
    
    print("✅ Done! Running status audit again:")
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
    
    # We acquire a lock before command, run command, and release lock
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
        
        # Save task details
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
    print("\033[1;36mTERMUX BACKGROUND STABILITY MANAGER\033[0m")
    print()
    print("\033[1mStability:\033[0m")
    print("  optimize status             Quick audit (compact one-liner)")
    print("  optimize status -f          Full detailed audit with descriptions")
    print("  optimize fix                Optimize via ADB (phantom limit → 2048, battery whitelist)")
    print()
    print("\033[1mBackground Tasks:\033[0m")
    print("  optimize run <name> <cmd>   Launch command in background with WakeLock & logging")
    print("  optimize list               List all active background tasks")
    print("  optimize stop <name>        Terminate a running background task")
    print("  optimize log <name>         Show log path and tail last 20 lines")
    print()
    print("\033[1mExamples:\033[0m")
    print("  optimize run myserver \"python3 -m http.server 8080\"")
    print("  optimize stop myserver")
    print("  optimize log myserver")
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
    elif cmd == "fix":
        fix_settings()
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
