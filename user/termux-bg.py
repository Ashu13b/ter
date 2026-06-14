import subprocess, sys, re, os, json, time

TASK_FILE = os.path.expanduser("~/.termux/bg_tasks.json")
LOG_DIR = os.path.expanduser("~/.termux/bg_logs")

def run_adb(args):
    cmd = ["adb", "-s", "127.0.0.1:5555"] + args
    try:
        proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=15)
        return proc.stdout.replace('\r', ''), proc.stderr.replace('\r', ''), proc.returncode
    except Exception as e:
        return "", str(e), -1

def get_wake_lock_status():
    # Query dumpsys power to see if com.termux holds a wake lock
    stdout, _, _ = run_adb(["shell", "dumpsys power"])
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

def check_battery_optimization():
    stdout, _, _ = run_adb(["shell", "dumpsys deviceidle whitelist"])
    return "com.termux" in stdout

def check_phantom_processes():
    stdout_enabled, _, _ = run_adb(["shell", "settings get global settings_enable_monitor_phantom_procs"])
    stdout_max, _, _ = run_adb(["shell", "device_config get activity_manager max_phantom_processes"])
    
    enabled = stdout_enabled.strip().lower() != "false"
    # It is optimized if monitor is false
    return not enabled

def show_status():
    print("\n\033[1;35m============================================================\033[0m")
    print("          \033[1mTERMUX BACKGROUND STABILITY AUDIT\033[0m")
    print("\033[1;35m============================================================\033[0m")
    
    # 1. WakeLock
    wl = get_wake_lock_status()
    wl_status = "\033[1;32m[ACTIVE]\033[0m (Prevents CPU from entering deep sleep)" if wl else "\033[1;33m[INACTIVE]\033[0m (CPU can sleep, pausing tasks)"
    print(f"  • WakeLock: {wl_status}")
    
    # 2. Phantom Process Monitor
    phantom_opt = check_phantom_processes()
    phantom_status = "\033[1;32m[OPTIMIZED]\033[0m (Disabled, processes won't be killed)" if phantom_opt else "\033[1;31m[LIMITING]\033[0m (Enabled, Android kills background child tasks)"
    print(f"  • Phantom Process Killer: {phantom_status}")
    
    # 3. Battery Saver Whitelist
    battery_opt = check_battery_optimization()
    battery_status = "\033[1;32m[EXEMPTED]\033[0m (Whitelisted from App Standby & Doze)" if battery_opt else "\033[1;31m[OPTIMIZED (RESTRICTED)]\033[0m (Android will suspend app in idle)"
    print(f"  • Battery Optimization: {battery_status}")
    print("\033[1;35m------------------------------------------------------------\033[0m")
    
    if not phantom_opt or not battery_opt:
        print("💡 Some background settings are not optimized. Run: \033[1;36mtermux-bg fix\033[0m")
    else:
        print("✅ Termux is fully optimized to run indefinitely in the background!")
    print()

def fix_settings():
    print("\n⚡ Optimizing Termux background permissions...")
    
    # 1. Disable phantom process killer
    print("  🛠️ Disabling Phantom Process Killer...")
    run_adb(["shell", "settings put global settings_enable_monitor_phantom_procs false"])
    run_adb(["shell", "device_config put activity_manager max_phantom_processes 2147483647"])
    
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
    
    print("\n📦 Active Background Tasks:")
    count = 0
    for name, info in list(tasks.items()):
        if is_pid_running(info["pid"]):
            running[name] = info
            count += 1
            print(f"  • \033[1m{name:<15}\033[0m | PID: {info['pid']:<6} | Started: {info['started']}")
            print(f"    ↳ Cmd: {info['command']}")
            print(f"    ↳ Log: {info['log']}")
        else:
            pass
            
    if count == 0:
        print("  (No active background tasks running)")
    print()
    
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
    print("\033[1mTERMUX BACKGROUND STABILITY MANAGER\033[0m")
    print("Usage:")
    print("  termux-bg status             Audit background stability states")
    print("  termux-bg fix                Optimize settings via ADB (disables phantom killer, exempts standby)")
    print("  termux-bg run <name> <cmd>   Launch command safely in background with WakeLocks & Notifications")
    print("  termux-bg list               List active running background tasks")
    print("  termux-bg stop <name>        Terminate a background task")
    print("  termux-bg log <name>         Show log path or print tail of logs")
    print()

def main():
    args = sys.argv[1:]
    if not args:
        print_help()
        sys.exit(0)
        
    cmd = args[0]
    if cmd == "status":
        show_status()
    elif cmd == "fix":
        fix_settings()
    elif cmd == "run":
        if len(args) < 3:
            print("❌ Error: Missing task name or command.")
            print("Usage: termux-bg run <name> \"<command>\"")
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
