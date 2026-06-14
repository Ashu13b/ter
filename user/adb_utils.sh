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

    python3 "$HOME/.local/bin/adb-audit.py" "$key"
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
    python3 "$HOME/.local/bin/adb-autostart.py"
}

# ── 9. Standby Bucket Controller ──
adb-standby() {
    if ! adb devices | grep -q "127.0.0.1:5555[[:space:]]*device"; then
        echo -e "${C_RED}❌ ADB loopback is offline. Run adbcon first.${C_RESET}"
        return 1
    fi
    python3 "$HOME/.local/bin/adb-standby.py"
}
