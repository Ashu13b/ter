# ── TER OS: ADB-Powered System Utilities ──

_get_adb_device() {
    local devs; devs=$(adb devices 2>/dev/null | tail -n +2 | grep -v "unauthorized" | awk '{print $1}')
    if [ -z "$devs" ]; then
        echo ""
        return 1
    fi
    if echo "$devs" | grep -q "127.0.0.1:5555"; then
        echo "127.0.0.1:5555"
    elif echo "$devs" | grep -q "emulator"; then
        echo "$devs" | grep "emulator" | head -n 1
    else
        echo "$devs" | head -n 1
    fi
}

# ── 1. Device System Metrics ──
adb-sysinfo() {
    if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
        echo -e "${C_BOLD}${C_CYAN}─── DEVICE SYSTEM METRICS HELP ───${C_RESET}"
        echo "Usage: adb-sysinfo"
        echo ""
        echo "Description:"
        echo "  Queries the connected device via ADB to fetch and display:"
        echo "    • Product Model name"
        echo "    • Android OS version"
        echo "    • Battery Level, Temperature (°C), and Charge Status"
        echo "    • Top 5 active CPU-consuming processes"
        return 0
    fi

    local dev; dev=$(_get_adb_device)
    if [ -z "$dev" ]; then
        echo -e "${C_RED}❌ No active ADB device found. Run adbcon first.${C_RESET}"
        return 1
    fi
    
    echo -e "\n${C_BOLD}${C_CYAN}─── DEVICE SYSTEM METRICS ───${C_RESET}"
    local model; model=$(adb -s "$dev" shell getprop ro.product.model | tr -d '\r')
    local android_ver; android_ver=$(adb -s "$dev" shell getprop ro.build.version.release | tr -d '\r')
    
    # Parse battery status
    local battery_info; battery_info=$(adb -s "$dev" shell dumpsys battery 2>/dev/null | tr -d '\r')
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
    local cpu_load; cpu_load=$(adb -s "$dev" shell top -n 1 -m 5 2>/dev/null | grep -E "%" | head -n 5)

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
    if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
        echo -e "${C_BOLD}${C_CYAN}─── INSTANT SCREENSHOT GRABBER HELP ───${C_RESET}"
        echo "Usage: adb-screengrab"
        echo ""
        echo "Description:"
        echo "  Captures the phone's screen, pulls the PNG image to your current"
        echo "  Termux directory with a timestamped filename, deletes the temp file"
        echo "  from the phone, and opens it using the default system viewer."
        return 0
    fi

    local dev; dev=$(_get_adb_device)
    if [ -z "$dev" ]; then
        echo -e "${C_RED}❌ No active ADB device found. Run adbcon first.${C_RESET}"
        return 1
    fi
    
    local filename="screenshot_$(date +%Y%m%d_%H%M%S).png"
    local local_dir; local_dir=$(pwd)
    
    echo -e "📸 Capturing phone screen..."
    adb -s "$dev" shell screencap -p /sdcard/Download/tmp_screenshot.png
    
    echo -e "📥 Pulling image to workspace..."
    adb -s "$dev" pull /sdcard/Download/tmp_screenshot.png "$local_dir/$filename" >/dev/null 2>&1
    adb -s "$dev" shell rm /sdcard/Download/tmp_screenshot.png
    
    echo -e "🎉 Screenshot saved in local folder as: ${C_GREEN}$local_dir/$filename${C_RESET}"
    if command -v termux-open &>/dev/null; then
        termux-open "$local_dir/$filename"
    fi
}

# ── 3. Consolidated App Manager & Optimizer ──
adb-manage() {
    if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
        python3 "$HOME/.shell.d/user/adb-manage.py" "$@"
        return 0
    fi

    local dev; dev=$(_get_adb_device)
    if [ -z "$dev" ]; then
        echo -e "${C_RED}❌ No active ADB device found. Run adbcon first.${C_RESET}"
        return 1
    fi
    python3 "$HOME/.shell.d/user/adb-manage.py" "$@"
}

# ── 5. System Logcat Streamer & Filter ──
adb-logcat() {
    if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
        echo -e "${C_BOLD}${C_CYAN}─── SYSTEM LOGCAT STREAMER HELP ───${C_RESET}"
        echo "Usage: adb-logcat [filter_query]"
        echo ""
        echo "Description:"
        echo "  Streams Android system logs (logcat) in real time."
        echo "  If a filter query is specified, it streams only log lines matching"
        echo "  that string (case-insensitive filter)."
        return 0
    fi

    local dev; dev=$(_get_adb_device)
    if [ -z "$dev" ]; then
        echo -e "${C_RED}❌ No active ADB device found. Run adbcon first.${C_RESET}"
        return 1
    fi
    if [ -n "$1" ]; then
        echo -e "📋 Streaming system logs for filter: ${C_YELLOW}$1${C_RESET} (Press Ctrl+C to exit)..."
        adb -s "$dev" logcat | grep -i "$1"
    else
        echo -e "📋 Streaming system logs (Press Ctrl+C to exit)..."
        adb -s "$dev" logcat
    fi
}

# ── 6. Master Security & Privacy Audit Engine ──
adb-audit() {
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

    local dev; dev=$(_get_adb_device)
    if [ -z "$dev" ]; then
        echo -e "${C_RED}❌ No active ADB device found. Run adbcon first.${C_RESET}"
        return 1
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

    python3 "$HOME/.shell.d/user/adb-audit.py" "$key"
}
