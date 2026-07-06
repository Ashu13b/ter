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

# ── Developer Options quick-toggle (`dvop`) ──
# Flips `development_settings_enabled` (the flag Play Integrity, GPS-spoof
# detectors and most banking apps actually read). No phone reboot required.
#
# CAUTION: `dvop off` also kills the Wireless Debugging daemon on most
# Android builds, so it disconnects this ADB session. Recovery:
#   Already paired once (usual case):
#     1. Phone: Settings → Developer options → toggle ON (top switch)
#     2. Phone: Wireless debugging → toggle ON
#     3. Termux: run `adbcon` (reconnects on the same loopback port)
#   Never paired before / port changed:
#     4. Additionally: same Wi-Fi network as Termux, then `adbcon` option 2
#        (pair) with the code shown on the phone.
dvop() {
    local dev; dev=$(_get_adb_device)
    if [ -z "$dev" ]; then
        echo -e "${C_RED}❌ No active ADB device. Run adbcon first.${C_RESET}"
        return 1
    fi

    local get_state
    get_state() {
        adb -s "$dev" shell settings get global development_settings_enabled 2>/dev/null | tr -d '\r'
    }

    local force=0
    local silent=0
    for a in "$@"; do
        [ "$a" = "-y" ] || [ "$a" = "-f" ] && force=1
        [ "$a" = "-s" ] || [ "$a" = "--silent" ] && silent=1
    done

    case "$1" in
        ""|status)
            local s; s=$(get_state)
            [ "$silent" -ne 1 ] && ( [ "$s" = "1" ] && echo -e "dvop: ${C_GREEN}ON${C_RESET}" || echo -e "dvop: ${C_YELLOW}OFF${C_RESET}" )
            ;;
        on)
            adb -s "$dev" shell settings put global development_settings_enabled 1 >/dev/null
            [ "$silent" -ne 1 ] && echo -e "dvop: ${C_GREEN}ON${C_RESET} (Settings menu will show Developer Options)"
            ;;
        off)
            if [ "$force" -ne 1 ]; then
                echo -e "${C_YELLOW}⚠  This also disables Wireless Debugging — you will lose this ADB session.${C_RESET}"
                echo "   Recovery (if previously paired): phone Settings → Developer options ON"
                echo "   → Wireless debugging ON → run \`adbcon\`."
                echo "   New pairing also needs same Wi-Fi + pairing code."
                echo -n "   Continue? [y/N] "
                read yn
                case "$yn" in [Yy]*) ;; *) echo "Cancelled."; return 0;; esac
            fi
            adb -s "$dev" shell settings put global development_settings_enabled 0 >/dev/null
            [ "$silent" -ne 1 ] && echo -e "dvop: ${C_YELLOW}OFF${C_RESET} (hidden from apps — no reboot needed)"
            ;;
        toggle)
            local s; s=$(get_state)
            if [ "$s" = "1" ]; then
                if [ "$force" -eq 1 ]; then
                    dvop off -f $( [ "$silent" -eq 1 ] && echo "-s" )
                else
                    dvop off
                fi
            else
                dvop on $( [ "$silent" -eq 1 ] && echo "-s" )
            fi
            ;;
        usb)
            local sub="$2"
            if [ -z "$sub" ] || [ "$sub" = "status" ]; then
                local u; u=$(adb -s "$dev" shell settings get global adb_enabled 2>/dev/null | tr -d '\r')
                [ "$silent" -ne 1 ] && ( [ "$u" = "1" ] && echo -e "dvop usb (USB Debugging): ${C_GREEN}ON${C_RESET}" || echo -e "dvop usb (USB Debugging): ${C_YELLOW}OFF${C_RESET}" )
            elif [ "$sub" = "on" ]; then
                adb -s "$dev" shell settings put global adb_enabled 1 >/dev/null
                [ "$silent" -ne 1 ] && echo -e "dvop usb (USB Debugging): ${C_GREEN}ON${C_RESET}"
            elif [ "$sub" = "off" ]; then
                # Safe check: if connected over physical USB, warn the user.
                if [ "$force" -ne 1 ] && adb -s "$dev" shell getprop sys.usb.state 2>/dev/null | grep -q "adb"; then
                    echo -e "${C_YELLOW}⚠  You are currently connected via physical USB. Disabling USB Debugging will close this session.${C_RESET}"
                    echo -n "   Continue? [y/N] "
                    read yn
                    case "$yn" in [Yy]*) ;; *) echo "Cancelled."; return 0;; esac
                fi
                adb -s "$dev" shell settings put global adb_enabled 0 >/dev/null
                [ "$silent" -ne 1 ] && echo -e "dvop usb (USB Debugging): ${C_YELLOW}OFF${C_RESET}"
            else
                echo "Usage: dvop usb [on|off]"
            fi
            ;;
        -h|--help|help)
            echo "Usage: dvop [on|off|toggle|status|usb]  [-f/-y skip confirmation] [-s/--silent run silently]"
            echo "  Flips development_settings_enabled via ADB. Requires adbcon."
            echo "  Effect is immediate — no phone restart needed."
            echo "  Subcommands:"
            echo "    on|off|toggle  Enable/disable main Developer Options menu."
            echo "    usb [on|off]   Enable/disable physical USB Debugging (adb_enabled)."
            echo "  Warning: 'off' also stops Wireless Debugging → recover manually on phone."
            ;;
        *)
            echo "Unknown: $1  (use: on|off|toggle|status)"
            return 1
            ;;
    esac
}

# ── 7. Smart APK Installer ──
adb-apk() {
    if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
        echo -e "${C_BOLD}${C_CYAN}─── SMART APK INSTALLER HELP ───${C_RESET}"
        echo "Usage: adb-apk [file.apk ...]"
        echo ""
        echo "Description:"
        echo "  Install APK files to your device via ADB with friendly"
        echo "  error handling and convenience features."
        echo ""
        echo "Options:"
        echo "  adb-apk                   Browse & pick APKs from Downloads"
        echo "  adb-apk app.apk           Install a single APK"
        echo "  adb-apk *.apk             Install multiple APKs"
        echo "  adb-apk chrome            Fuzzy search by name"
        echo "  adb-apk /path/to/dir      Search inside a directory"
        echo "  adb-apk -r app.apk        Reinstall (keep app data)"
        echo "  adb-apk -f app.apk        Force install (skip confirmation)"
        echo "  adb-apk -h, --help        Show this help"
        return 0
    fi

    # Check prerequisites
    if ! command -v adb &>/dev/null; then
        echo -e "${C_RED}❌ Prerequisites missing: 'adb' command not found.${C_RESET}"
        echo -e "   Please install android-tools first: ${C_GREEN}pkg install android-tools${C_RESET}"
        return 1
    fi

    # Friendly hint if aapt/aapt2 is missing (used for parsing package details)
    if ! command -v aapt2 &>/dev/null && ! command -v aapt &>/dev/null; then
        echo -e "💡 ${C_DIM}Tip: Install 'aapt' to view package names & versions before installing: pkg install aapt${C_RESET}"
    fi

    local dev; dev=$(_get_adb_device)
    if [ -z "$dev" ]; then
        echo -e "${C_RED}❌ No active ADB device found. Run ${C_BOLD}adbcon${C_RESET}${C_RED} first.${C_RESET}"
        return 1
    fi

    # Ensure Play Protect verification for ADB installs is disabled to guarantee silent installation
    local verifier_state; verifier_state=$(adb -s "$dev" shell settings get global verifier_verify_adb_installs 2>/dev/null | tr -d '\r')
    if [ "$verifier_state" = "1" ]; then
        echo -e "🛡️  ${C_YELLOW}Disabling Play Protect verification for ADB installs to ensure silent install...${C_RESET}"
        adb -s "$dev" shell settings put global verifier_verify_adb_installs 0 >/dev/null 2>&1
        local check_state; check_state=$(adb -s "$dev" shell settings get global verifier_verify_adb_installs 2>/dev/null | tr -d '\r')
        if [ "$check_state" = "0" ]; then
            echo -e "✅ ${C_GREEN}Silent mode enabled.${C_RESET}"
        else
            echo -e "⚠️  ${C_YELLOW}Could not disable verification automatically. If prompted on screen, please tap 'Allow'.${C_RESET}"
        fi
    fi

    # Parse flags
    local reinstall_flag=""
    local skip_confirm=0
    local apk_files=()
    for arg in "$@"; do
        if [[ "$arg" == "-r" ]]; then
            reinstall_flag="-r"
        elif [[ "$arg" == "-y" ]] || [[ "$arg" == "--yes" ]] || [[ "$arg" == "-f" ]] || [[ "$arg" == "--force" ]]; then
            skip_confirm=1
        else
            apk_files+=("$arg")
        fi
    done

    # Resolve APK files — support exact path, directory, or fuzzy search
    if [ ${#apk_files[@]} -eq 0 ] || { [ ${#apk_files[@]} -eq 1 ] && [ ! -f "${apk_files[0]}" ]; }; then
        if ! command -v fzf &>/dev/null; then
            echo -e "${C_RED}❌ fzf not installed — needed for APK browsing.${C_RESET}"
            echo "Usage: adb-apk <exact-path-to-file.apk>"
            return 1
        fi

        local query=""
        local search_dirs=("$(pwd)")
        [ "$(pwd)" != "$HOME" ] && search_dirs+=("$HOME")
        [ -d "$HOME/storage/downloads" ] && search_dirs+=("$HOME/storage/downloads")
        [ -d "$HOME/Downloads" ] && search_dirs+=("$HOME/Downloads")
        [ -d "/storage/emulated/0/workspace" ] && search_dirs+=("/storage/emulated/0/workspace")

        # If user gave an arg that isn't a file, use it as search hint
        if [ ${#apk_files[@]} -eq 1 ]; then
            local hint="${apk_files[0]}"
            if [ -d "$hint" ]; then
                # It's a directory — search inside it
                search_dirs=("$hint")
            else
                # It's a fuzzy query
                query="$hint"
            fi
        fi

        echo -e "🔍 ${C_CYAN}Searching for APK files...${C_RESET}"
        local selected
        selected=$(find "${search_dirs[@]}" -maxdepth 3 -name "*.apk" -type f 2>/dev/null | sort -u | fzf --height=15 --reverse --query="$query" --prompt="Select APK > " --header="Pick an APK to install (ESC to cancel)")

        if [ -z "$selected" ]; then
            echo -e "${C_YELLOW}Cancelled.${C_RESET}"
            return 0
        fi
        apk_files=("$selected")
    fi

    # Install each APK
    local total=${#apk_files[@]}
    local installed=0
    local failed=0

    for apk in "${apk_files[@]}"; do
        # Validate file
        if [ ! -f "$apk" ]; then
            echo -e "${C_RED}❌ File not found: $apk${C_RESET}"
            ((failed++))
            continue
        fi

        if [[ "$apk" != *.apk ]]; then
            echo -e "${C_RED}❌ Not an APK file: $apk${C_RESET}"
            ((failed++))
            continue
        fi

        local basename_apk; basename_apk=$(basename "$apk")
        local size; size=$(du -h "$apk" 2>/dev/null | awk '{print $1}')

        echo -e "\n${C_BOLD}${C_CYAN}── APK: ${C_YELLOW}$basename_apk${C_RESET} ${C_DIM}($size)${C_RESET}"
        echo -e "  📂 Path: ${C_DIM}$apk${C_RESET}"

        # Try to extract package info
        local pkg_info=""
        if command -v aapt2 &>/dev/null; then
            pkg_info=$(aapt2 dump badging "$apk" 2>/dev/null | head -n 1)
        elif command -v aapt &>/dev/null; then
            pkg_info=$(aapt dump badging "$apk" 2>/dev/null | head -n 1)
        fi

        if [ -n "$pkg_info" ]; then
            local pkg_name; pkg_name=$(echo "$pkg_info" | grep -oP "name='\K[^']+")
            local pkg_ver; pkg_ver=$(echo "$pkg_info" | grep -oP "versionName='\K[^']+")
            [ -n "$pkg_name" ] && echo -e "  📦 Package: ${C_GREEN}$pkg_name${C_RESET}"
            [ -n "$pkg_ver" ] && echo -e "  📋 Version: ${C_BLUE}$pkg_ver${C_RESET}"
        fi

        # Confirm before installing (skip with -y)
        if [ $skip_confirm -eq 0 ]; then
            echo -ne "  👉 Install this APK? (Y/n): "
            read confirm_install
            if [[ "$confirm_install" =~ ^[Nn]$ ]]; then
                echo -e "  ${C_YELLOW}Skipped.${C_RESET}"
                continue
            fi
        fi

        # Run install
        echo -e "  ⏳ Installing..."
        local result
        result=$(adb -s "$dev" install $reinstall_flag "$apk" 2>&1)
        local exit_code=$?

        if echo "$result" | grep -qi "success"; then
            echo -e "  ✅ ${C_GREEN}Installed successfully!${C_RESET}"
            ((installed++))

            # Offer to launch (single APK only)
            if [ $total -eq 1 ] && [ -n "$pkg_info" ]; then
                local pkg_name; pkg_name=$(echo "$pkg_info" | grep -oP "name='\K[^']+")
                if [ -n "$pkg_name" ]; then
                    echo -ne "  🚀 Launch now? (y/N): "
                    read launch_choice
                    if [[ "$launch_choice" =~ ^[Yy]$ ]]; then
                        adb -s "$dev" shell monkey -p "$pkg_name" -c android.intent.category.LAUNCHER 1 > /dev/null 2>&1
                        echo -e "  ${C_GREEN}App launched!${C_RESET}"
                    fi
                fi
            fi
        else
            ((failed++))
            # Friendly error translation
            if echo "$result" | grep -qi "INSTALL_FAILED_UPDATE_INCOMPATIBLE"; then
                echo -e "  ${C_RED}❌ Signature mismatch — the installed version was signed with a different key.${C_RESET}"
                echo -ne "  🗑️  Uninstall existing app and retry? (y/N): "
                read retry_choice
                if [[ "$retry_choice" =~ ^[Yy]$ ]]; then
                    local pkg_name; pkg_name=$(echo "$result" | grep -oP 'Package \K[^ ]+' || echo "")
                    if [ -n "$pkg_name" ]; then
                        adb -s "$dev" uninstall "$pkg_name" > /dev/null 2>&1
                        result=$(adb -s "$dev" install $reinstall_flag "$apk" 2>&1)
                        if echo "$result" | grep -qi "success"; then
                            echo -e "  ✅ ${C_GREEN}Reinstalled successfully!${C_RESET}"
                            ((failed--)); ((installed++))
                        else
                            echo -e "  ${C_RED}❌ Still failed: $result${C_RESET}"
                        fi
                    else
                        echo -e "  ${C_RED}Could not detect package name to uninstall.${C_RESET}"
                    fi
                fi
            elif echo "$result" | grep -qi "INSTALL_FAILED_ALREADY_EXISTS"; then
                echo -e "  ${C_YELLOW}⚠️  App already installed. Use ${C_BOLD}adb-apk -r${C_RESET}${C_YELLOW} to update.${C_RESET}"
            elif echo "$result" | grep -qi "INSTALL_FAILED_INSUFFICIENT_STORAGE"; then
                echo -e "  ${C_RED}❌ Not enough storage on device.${C_RESET}"
            elif echo "$result" | grep -qi "INSTALL_FAILED_OLDER_SDK"; then
                echo -e "  ${C_RED}❌ APK requires a newer Android version than your device.${C_RESET}"
            elif echo "$result" | grep -qi "INSTALL_PARSE_FAILED_NO_CERTIFICATES"; then
                echo -e "  ${C_RED}❌ APK is not signed — may be corrupted or tampered.${C_RESET}"
            elif echo "$result" | grep -qi "INSTALL_FAILED_VERSION_DOWNGRADE"; then
                echo -e "  ${C_YELLOW}⚠️  Newer version already installed. Use ${C_BOLD}adb install -d${C_RESET}${C_YELLOW} to force downgrade.${C_RESET}"
            else
                echo -e "  ${C_RED}❌ Install failed: $result${C_RESET}"
            fi
        fi
    done

    # Summary for batch installs
    if [ $total -gt 1 ]; then
        echo -e "\n${C_BOLD}── Summary ──${C_RESET}"
        echo -e "  ✅ Installed: ${C_GREEN}$installed${C_RESET} / $total"
        [ $failed -gt 0 ] && echo -e "  ❌ Failed: ${C_RED}$failed${C_RESET}"
    fi
}
