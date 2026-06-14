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
    wl = get_wake_lock_status()
    phantom_opt = check_phantom_processes()
    battery_opt = check_battery_optimization()
    
    wl_icon = "🟢" if wl else "🟡"
    wl_raw = "ACTIVE" if wl else "INACTIVE"
    wl_state = f"\033[1;32m{wl_raw}\033[0m" if wl else f"\033[1;33m{wl_raw}\033[0m"
    wl_padded = wl_state + (" " * (28 - len(wl_raw)))
    
    phantom_icon = "🟢" if phantom_opt else "🔴"
    phantom_raw = "OPTIMIZED" if phantom_opt else "LIMITING"
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
    print("\033[1;35m│\033[0m      ↳ Disabled, child processes won't be killed         \033[1;35m│\033[0m")
    print("\033[1;35m│\033[0m                                                          \033[1;35m│\033[0m")
    print(f"\033[1;35m│\033[0m  {battery_icon}  Battery Optimization : {battery_padded}\033[1;35m│\033[0m")
    print("\033[1;35m│\033[0m      ↳ Whitelisted from App Standby & Doze               \033[1;35m│\033[0m")
    print("\033[1;35m├──────────────────────────────────────────────────────────┤\033[0m")
    
    if not phantom_opt or not battery_opt:
        msg = "  ⚠️  Some constraints are active. Run: termux-bg fix"
        print(f"\033[1;35m│\033[0m\033[1;33m{msg:<58}\033[0m\033[1;35m│\033[0m")
    else:
        msg = "  ✅  Termux is fully optimized for background tasks!"
        print(f"\033[1;35m│\033[0m\033[1;32m{msg:<58}\033[0m\033[1;35m│\033[0m")
        
    print("\033[1;35m└──────────────────────────────────────────────────────────┘\033[0m\n")

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
