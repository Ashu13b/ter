# ── TER OS: ADB-Powered System Utilities ──

# ── 1. Device System Metrics ──
sysinfo() {
    if ! adb devices | grep -q "127.0.0.1:5555[[:space:]]*device"; then
        echo -e "${C_RED}❌ ADB loopback is offline. Run adbcon first.${C_RESET}"
        return 1
    fi
    
    echo -e "\n${C_BOLD}${C_CYAN}─── DEVICE SYSTEM METRICS ───${C_RESET}"
    local model; model=$(adb -s 127.0.0.1:5555 shell getprop ro.product.model | tr -d '\r')
    local android_ver; android_ver=$(adb -s 127.0.0.1:5555 shell getprop ro.build.version.release | tr -d '\r')
    
    # Parse battery status
    local battery_info; battery_info=$(adb -s 127.0.0.1:5555 shell dumpsys battery 2>/dev/null | tr -d '\r')
    local level; level=$(echo "$battery_info" | grep "level:" | awk '{print $2}')
    local temp; temp=$(echo "$battery_info" | grep "temperature:" | awk '{print $2}')
    local temp_c; temp_c=$(python3 -c "print($temp / 10.0)" 2>/dev/null || echo "?")
    local status_code; status_code=$(echo "$battery_info" | grep "status:" | awk '{print $2}')
    
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
screen-grab() {
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
app-manage() {
    if ! adb devices | grep -q "127.0.0.1:5555[[:space:]]*device"; then
        echo -e "${C_RED}❌ ADB loopback is offline. Run adbcon first.${C_RESET}"
        return 1
    fi

    echo -e "\n${C_BOLD}${C_CYAN}─── APP LIFECYCLE MANAGER ───${C_RESET}"
    echo " [1] List installed third-party apps"
    echo " [2] Freeze an app (Disable background battery drain)"
    echo " [3] Unfreeze an app (Re-enable app access)"
    read -p "👉 Selection (1-3): " choice
    
    case "$choice" in
        1)
            echo -e "\n📦 Installed Third-Party Packages:"
            adb -s 127.0.0.1:5555 shell pm list packages -3 | tr -d '\r' | cut -d':' -f2 | sort | sed 's/^/  /'
            ;;
        2)
            read -p "👉 Enter package name to freeze: " pkg
            if [ -n "$pkg" ]; then
                echo -e "❄️ Freezing package $pkg..."
                adb -s 127.0.0.1:5555 shell pm disable-user "$pkg"
                echo -e "✅ Package disabled. It will not run or consume battery."
            fi
            ;;
        3)
            read -p "👉 Enter package name to unfreeze: " pkg
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
