#!/bin/bash

_adbcon_valid_ipv4() {
    local ip="$1" o1 o2 o3 o4 extra n
    [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
    IFS=. read -r o1 o2 o3 o4 extra <<< "$ip"
    [ -z "$extra" ] || return 1
    for n in "$o1" "$o2" "$o3" "$o4"; do (( 10#$n <= 255 )) || return 1; done
}

_adbcon_valid_port() {
    [[ "$1" =~ ^[0-9]{1,5}$ ]] && (( 10#$1 >= 1 && 10#$1 <= 65535 ))
}

_adbcon_valid_pair_code() {
    [[ "$1" =~ ^[0-9]{6}$ ]]
}

_adbcon_parse_endpoint() {
    local raw="$1"
    raw=$(printf '%s' "$raw" | tr -d '[:space:]')
    if [[ "$raw" == *:* ]]; then
        PARSED_IP="${raw%%:*}"
        PARSED_PORT="${raw##*:}"
    else
        PARSED_IP=""
        PARSED_PORT="$raw"
    fi
}

_adbcon_timed() {
    local seconds="${ADBCON_TIMEOUT_SECONDS:-20}"
    if ! [[ "$seconds" =~ ^[0-9]{1,2}$ ]] || (( 10#$seconds < 1 || 10#$seconds > 60 )); then
        seconds=20
    fi
    timeout "$seconds" adb "$@"
}

_adbcon_pair_succeeded() {
    local exit_code="$1" output="$2"
    [ "$exit_code" -eq 0 ] || return 1
    printf '%s\n' "$output" | grep -Eqi '(^|[[:space:]])successfully paired([[:space:]]|$)|pairing successful'
}

# Remember the last endpoint that actually connected, so reconnects after a
# reboot/ADB restart are a single `adbcon` with no wizard.
_adbcon_cache_file() {
    printf '%s' "${XDG_CONFIG_HOME:-$HOME/.config}/ter/adb_last"
}

_adbcon_cache_save() {
    local f; f=$(_adbcon_cache_file)
    mkdir -p "${f%/*}" 2>/dev/null && printf '%s\n' "$1" > "$f" 2>/dev/null || true
}

_adbcon_status() {
    echo -e "\e[1;36m══ ADB STATUS & DIAGNOSTICS ══\e[0m"
    if ! command -v adb >/dev/null 2>&1; then
        echo -e "❌ android-tools: \e[1;31mNOT INSTALLED\e[0m (run: pkg install android-tools)"
        return 127
    fi
    local LOCAL_LOOPBACK="127.0.0.1:5555"
    local dev_output
    dev_output=$(_adbcon_timed devices 2>/dev/null)
    local dev_exit=$?
    if [ $dev_exit -ne 0 ] || [ -z "$dev_output" ]; then
        echo -e "○ ADB Server: \e[90mOFFLINE\e[0m"
        echo -e "   Run 'adbcon' to start server and connect."
        return 0
    fi
    echo -e "✓ ADB Server: \e[1;32mRUNNING\e[0m"

    # Check loopback
    if echo "$dev_output" | grep -qE "^${LOCAL_LOOPBACK}[[:space:]]+device"; then
        echo -e "✓ Loopback Channel ($LOCAL_LOOPBACK): \e[1;32mCONNECTED & LOCKED\e[0m"
    elif echo "$dev_output" | grep -qE "^${LOCAL_LOOPBACK}[[:space:]]+offline"; then
        echo -e "⚠️  Loopback Channel ($LOCAL_LOOPBACK): \e[1;33mOFFLINE\e[0m (run 'adb reconnect offline')"
    else
        echo -e "○ Loopback Channel ($LOCAL_LOOPBACK): \e[90mDISCONNECTED\e[0m"
    fi

    # Check other attached devices
    local other_devs
    other_devs=$(echo "$dev_output" | sed '1d' | grep -vE "^${LOCAL_LOOPBACK}[[:space:]]" | grep -E '\S' || true)
    if [ -n "$other_devs" ]; then
        echo -e "\n📡 Other Attached Device(s):"
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            echo -e "   • $line"
        done <<< "$other_devs"
    fi

    # Check Wi-Fi / IP link
    local sta_ip
    sta_ip=$(ifconfig 2>/dev/null | awk '/^wlan/ {w=1} /^[^ \t]/ && !/^wlan/ {w=0} w && /inet / {print $2}' | head -n 1)
    if [ -n "$sta_ip" ]; then
        echo -e "📡 Wi-Fi IP (Client): \e[1;32m$sta_ip\e[0m"
    fi
    return 0
}

adbcon() {
    local LOCAL_LOOPBACK="127.0.0.1:5555"
    local scan_ports=0
    local no_shell=0
    local direct_port=""
    local direct_pair=0
    local pair_port="" pair_code="" current_port=""
    local wizard_choice="" input_ip=""
    local is_disconnect=0

    # Parse arguments
    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help)
                echo "=========================================================="
                echo "            ADB CONNECTION MODULE GUIDE                   "
                echo "=========================================================="
                echo "Usage: adbcon [options | command | endpoint]"
                echo ""
                echo "Commands & Options:"
                echo "  adbcon                     Connect (auto-reconnects to last endpoint; wizard only if needed)"
                echo "  adbcon status, -s          Show ADB status and diagnostics"
                echo "  adbcon -c, --no-shell      Connect without dropping into a shell (never prompts when piped)"
                echo "  adbcon <port>              Direct connect to port on phone IP"
                echo "  adbcon <ip>:<port>         Direct connect to specific endpoint"
                echo "  adbcon pair <port> <code>  Pair directly using port and code"
                echo "  adbcon --scan              Scan for an already-paired wireless ADB port"
                echo "  adbcon -d, --exit          Disconnect and kill the active ADB server"
                echo "  adbcon -h, --help          Show this connection help manual"
                echo "=========================================================="
                return 0
                ;;
            -s|--status|status)
                _adbcon_status
                return $?
                ;;
            -c|--connect|--no-shell)
                no_shell=1
                shift
                ;;
            --scan)
                scan_ports=1
                shift
                ;;
            -d|--exit|disconnect)
                is_disconnect=1
                shift
                ;;
            pair)
                direct_pair=1
                shift
                if [ $# -ge 2 ]; then
                    pair_port="$1"
                    pair_code="$2"
                    shift 2
                fi
                ;;
            -*)
                echo "Unknown adbcon option: $1" >&2
                echo "Run 'adbcon --help' for usage." >&2
                return 2
                ;;
            *)
                if [ -z "$direct_port" ]; then
                    direct_port="$1"
                    shift
                else
                    echo "Unexpected argument: $1" >&2
                    return 2
                fi
                ;;
        esac
    done

    # Non-interactive stdin defaults to no-shell
    if [ ! -t 0 ]; then
        no_shell=1
    fi

    if ! command -v adb >/dev/null 2>&1; then
        echo "adbcon requires android-tools (run: pkg install android-tools)."
        return 127
    fi
    if ! command -v timeout >/dev/null 2>&1; then
        echo "adbcon requires timeout from coreutils (run: pkg install coreutils)."
        return 127
    fi

    if [ "$is_disconnect" -eq 1 ]; then
        echo -e "\e[1;34m[ ADB DISCONNECT ]\e[0m"
        _adbcon_timed disconnect >/dev/null 2>&1 || true
        if ! _adbcon_timed kill-server >/dev/null 2>&1; then
            echo "ADB server could not be stopped; it may still be running." >&2
            return 1
        fi
        echo "✨ ADB is completely offline."
        return 0
    fi

    # 1. Fast check for existing loopback channel (0ms overhead if already online)
    if _adbcon_timed devices 2>/dev/null | grep -qE "^${LOCAL_LOOPBACK}[[:space:]]+device"; then
        echo -e "🎉 \e[1;32mConnection is alive and locked in background!\e[0m"
        if [ "$no_shell" -eq 1 ]; then
            return 0
        fi
        echo -e "Dropping into shell...\n"
        adb -s "$LOCAL_LOOPBACK" shell
        return $?
    fi

    # If offline, attempt a quick reconnect
    if _adbcon_timed devices 2>/dev/null | grep -qE "^${LOCAL_LOOPBACK}[[:space:]]+offline"; then
        _adbcon_timed reconnect offline >/dev/null 2>&1 || true
        sleep 0.3
        if _adbcon_timed devices 2>/dev/null | grep -qE "^${LOCAL_LOOPBACK}[[:space:]]+device"; then
            echo -e "🎉 \e[1;32mLoopback channel revived from offline state!\e[0m"
            if [ "$no_shell" -eq 1 ]; then
                return 0
            fi
            echo -e "Dropping into shell...\n"
            adb -s "$LOCAL_LOOPBACK" shell
            return $?
        fi
    fi

    # Try connecting to loopback once
    _adbcon_timed connect "$LOCAL_LOOPBACK" >/dev/null 2>&1 || true
    if _adbcon_timed devices 2>/dev/null | grep -qE "^${LOCAL_LOOPBACK}[[:space:]]+device"; then
        echo -e "🎉 \e[1;32mConnected to existing loopback channel!\e[0m"
        if [ "$no_shell" -eq 1 ]; then
            return 0
        fi
        echo -e "Dropping into shell...\n"
        adb -s "$LOCAL_LOOPBACK" shell
        return $?
    fi

    # Reconnect to the last known-good endpoint, so a rebooted/restarted ADB
    # comes back with a single `adbcon` and no wizard.
    local cache_file; cache_file=$(_adbcon_cache_file)
    if [ -z "$direct_port" ] && [ "$direct_pair" -eq 0 ] && [ "$scan_ports" -eq 0 ] && [ -r "$cache_file" ]; then
        local last; last=$(cat "$cache_file" 2>/dev/null)
        if [ -n "$last" ]; then
            echo -e "↻ \e[1;36mTrying last known endpoint:\e[0m $last"
            _adbcon_timed connect "$last" >/dev/null 2>&1 || true
            sleep 0.6
            if _adbcon_timed devices 2>/dev/null | grep -qE "^${last}[[:space:]]+device"; then
                _adbcon_timed tcpip 5555 >/dev/null 2>&1 || true
                local lk=0 i
                for i in $(seq 1 6); do
                    sleep 0.5
                    _adbcon_timed connect "$LOCAL_LOOPBACK" >/dev/null 2>&1 || true
                    if _adbcon_timed devices 2>/dev/null | grep -qE "^${LOCAL_LOOPBACK}[[:space:]]+device"; then lk=1; break; fi
                done
                _adbcon_timed disconnect "$last" >/dev/null 2>&1 || true
                if [ "$lk" -eq 1 ]; then
                    echo -e "🎉 \e[1;32mReconnected via last known endpoint.\e[0m"
                    if [ "$no_shell" -eq 1 ]; then
                        return 0
                    fi
                    echo -e "Dropping into shell...\n"
                    adb -s "$LOCAL_LOOPBACK" shell
                    return $?
                fi
            fi
        fi
    fi

    # Check if a non-loopback device is already attached (e.g. active Wi-Fi channel)
    local existing_attached
    existing_attached=$(_adbcon_timed devices 2>/dev/null | sed '1d' | grep -vE "^${LOCAL_LOOPBACK}[[:space:]]" | awk '$2 == "device" {print $1}' | head -n 1)
    if [ -n "$existing_attached" ] && [ -z "$direct_port" ] && [ "$direct_pair" -eq 0 ]; then
        echo -e "📡 \e[1;32mExisting active device found:\e[0m $existing_attached"
        echo -e "🔄 \e[1;36mPromoting to offline loopback mode (port 5555)...\e[0m"
        _adbcon_timed -s "$existing_attached" tcpip 5555 >/dev/null 2>&1 || true
        local promoted=0
        for i in {1..5}; do
            sleep 0.5
            _adbcon_timed connect "$LOCAL_LOOPBACK" >/dev/null 2>&1 || true
            if _adbcon_timed devices 2>/dev/null | grep -qE "^${LOCAL_LOOPBACK}[[:space:]]+device"; then
                promoted=1
                break
            fi
        done
        if [ $promoted -eq 1 ]; then
            _adbcon_timed disconnect "$existing_attached" >/dev/null 2>&1 || true
            echo -e "🎉 \e[1;32mLoopback channel locked successfully!\e[0m"
            if [ "$no_shell" -eq 1 ]; then
                return 0
            fi
            echo -e "Dropping into shell...\n"
            adb -s "$LOCAL_LOOPBACK" shell
            return $?
        fi
    fi

    # Clean up stale loopback entry so it doesn't interfere
    _adbcon_timed disconnect "$LOCAL_LOOPBACK" >/dev/null 2>&1 || true

    # A script or non-interactive caller must never block on a hidden prompt.
    if [ ! -t 0 ] && [ -z "$direct_port" ] && [ "$direct_pair" -eq 0 ] && [ "$scan_ports" -eq 0 ]; then
        echo "No active ADB device, and stdin is not a TTY to pair interactively." >&2
        echo "Run 'adbcon' in a terminal, or pass an endpoint: adbcon <port|ip:port>." >&2
        return 1
    fi

    echo -e "\n\e[1;36m══ TERMUX SMART ADB WIZARD ══\e[0m\n"
    echo -e "⚠️  \e[33mBackground channel offline (Phone rebooted or ADB killed)\e[0m"
    echo -e "   \e[90mRecovery ladder if this was a \`dvop off\`:\e[0m"
    echo -e "   \e[90m  · Previously paired: turn Developer options ON, Wireless Debugging ON — reconnect below.\e[0m"
    echo -e "   \e[90m  · Fresh pair needed: same Wi-Fi as Termux, then pick option 2 with the phone's pairing code.\e[0m\n"

    # 2. Check Network (Best Effort)
    local IP STA_IP AP_IP
    # STA (client) — wlan0/wlan1: real Wi-Fi client link, only mode that unlocks Wireless Debugging.
    STA_IP=$(ifconfig 2>/dev/null | awk '/^wlan/ {w=1} /^[^ \t]/ && !/^wlan/ {w=0} w && /inet / {print $2}' | head -n 1)
    # AP (hotspot) — ap0/swlan0: phone is broadcasting, not joined as client. Doesn't help ADB.
    AP_IP=$(ifconfig 2>/dev/null | awk '/^(ap|swlan)/ {w=1} /^[^ \t]/ && !/^(ap|swlan)/ {w=0} w && /inet / {print $2}' | head -n 1)

    if [ -n "$STA_IP" ]; then
        IP="$STA_IP"
        echo -e "📡 \e[1;32mWi-Fi client link detected:\e[0m $IP"
    elif [ -n "$AP_IP" ]; then
        # Hotspot-only mode → Wireless Debugging refuses to activate. Abort with the reason.
        echo -e "❌ \e[1;31mOnly hotspot (AP) interface active:\e[0m $AP_IP"
        echo -e "   \e[90mAndroid's Wireless Debugging requires the phone to be a Wi-Fi CLIENT,\e[0m"
        echo -e "   \e[90mnot an access point. Join a real Wi-Fi network (any SSID, no internet\e[0m"
        echo -e "   \e[90mneeded), then rerun \`adbcon\`. See docs/dvop-experiment-findings.md.\e[0m"
        return 1
    else
        IP=$(ifconfig 2>/dev/null | awk '/inet / && !/127\.0\.0\.1/ && !/192\.0\.0\./ {print $2}' | head -n 1)
        [ -z "$IP" ] && IP=$(ip addr 2>/dev/null | grep -oP 'inet \K[0-9.]+' | grep -v '127.0.0.1' | head -n 1)
        if [ -z "$IP" ]; then
            IP="192.168.1.1"
            echo -e "⚠️  \e[33mNo Wi-Fi detected automatically — using fallback $IP.\e[0m"
        else
            echo -e "📡 \e[1;32mNetwork detected:\e[0m $IP"
        fi
    fi

    # Handle direct arguments (if port or endpoint provided)
    if [ -n "$direct_port" ]; then
        _adbcon_parse_endpoint "$direct_port"
        if [ -n "$PARSED_IP" ]; then
            if ! _adbcon_valid_ipv4 "$PARSED_IP"; then
                echo "Invalid IPv4 address: $PARSED_IP" >&2
                return 1
            fi
            IP="$PARSED_IP"
        fi
        current_port="$PARSED_PORT"
        if ! _adbcon_valid_port "$current_port"; then
            echo "Invalid connection port: $current_port" >&2
            return 1
        fi
    elif [ "$direct_pair" -eq 1 ]; then
        if [ -z "$pair_port" ] || [ -z "$pair_code" ]; then
            echo "Usage: adbcon pair <port|ip:port> <code>" >&2
            return 1
        fi
        _adbcon_parse_endpoint "$pair_port"
        if [ -n "$PARSED_IP" ]; then
            if ! _adbcon_valid_ipv4 "$PARSED_IP"; then
                echo "Invalid IPv4 address: $PARSED_IP" >&2
                return 1
            fi
            IP="$PARSED_IP"
        fi
        pair_port="$PARSED_PORT"
        if ! _adbcon_valid_port "$pair_port"; then
            echo "Invalid pairing port: $pair_port" >&2
            return 1
        fi
        if ! _adbcon_valid_pair_code "$pair_code"; then
            echo "Pairing code must contain exactly 6 digits." >&2
            return 1
        fi
        wizard_choice="2"
    else
        echo -ne "👉 Phone IP [\e[1;33m$IP\e[0m] — press Enter to use this, or type a different IP: "
        read input_ip
        local ORIG_IP="$IP"
        IP=${input_ip:-$IP}
        if ! _adbcon_valid_ipv4 "$IP"; then
            echo "Invalid IPv4 address: $IP"
            return 1
        fi

        # Subnet sanity check — if user typed an IP outside our /24, warn but don't block.
        if [ -n "$STA_IP" ] && [ "$IP" != "$ORIG_IP" ]; then
            local our_subnet="${STA_IP%.*}"
            local their_subnet="${IP%.*}"
            if [ "$our_subnet" != "$their_subnet" ]; then
                echo -e "⚠️  \e[33mPhone IP $IP is outside our subnet ($our_subnet.0/24).\e[0m"
                echo -e "   \e[90mLikely causes: different Wi-Fi networks, guest-network client isolation,\e[0m"
                echo -e "   \e[90mor VLAN separation. Port scan will probably find nothing.\e[0m"
            fi
        fi
    fi

    if [ "$scan_ports" -eq 1 ] && ! command -v python3 >/dev/null 2>&1; then
        echo "adbcon --scan requires python3 (run: pkg install python)."
        return 127
    fi

    echo -e "\n\e[1;35m[ REQUIRED PREPARATION ]\e[0m"
    echo -e "1. Go to phone \e[1;37mSettings\e[0m -> \e[1;37mDeveloper Options\e[0m."
    echo -e "2. Scroll down to \e[1;37mWireless Debugging\e[0m and turn it \e[1;32mON\e[0m."
    echo -e "   (If it asks to allow the network, click Allow/Always Allow)\n"

    # 3. Optional discovery is deliberately opt-in: broad scans are costly on phones.
    local ports=""
    local auto_connected=0
    local pairing_revoked=0

    if [ "$scan_ports" -eq 1 ]; then
        echo -e "🔍 \e[1;36mScanning for an already-paired Wireless Debugging port...\e[0m"
        if ! ports=$(timeout 30 python3 -c '
import socket, sys, concurrent.futures
ip = sys.argv[1]
def scan(p):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(0.05)
        if s.connect_ex((ip, p)) == 0:
            return p
    return None
with concurrent.futures.ThreadPoolExecutor(max_workers=300) as e:
    results = e.map(lambda p: scan(p), range(30000, 50000))
    for r in results:
        if r: print(r)
' "$IP" 2>/dev/null)
        then
            echo "Wireless ADB port scan failed or timed out after 30 seconds." >&2
            return 1
        fi

        for port in $ports; do
            echo -e "🔌 Found port \e[1;33m$port\e[0m. Testing connection..."
            _adbcon_timed connect "$IP:$port" >/dev/null 2>&1 || true
            sleep 0.4
            local dev_line
            dev_line=$(_adbcon_timed devices 2>/dev/null | grep -F "$IP:$port")
            if echo "$dev_line" | grep -qE "[[:space:]]device([[:space:]]|$)"; then
                auto_connected=1
                current_port=$port
                break
            elif echo "$dev_line" | grep -q "unauthorized"; then
                echo -e "🔒 \e[1;33mPort $port is open but the pairing is no longer trusted.\e[0m"
                _adbcon_timed disconnect "$IP:$port" >/dev/null 2>&1 || true
                pairing_revoked=1
                break
            else
                _adbcon_timed disconnect "$IP:$port" >/dev/null 2>&1 || true
            fi
        done

        if [ $pairing_revoked -eq 1 ]; then
            echo -e "   \e[90mFresh pair needed — skipping remaining port probes.\e[0m\n"
            wizard_choice="2"
        fi

        if [ $auto_connected -eq 1 ]; then
            echo -e "\n✅ \e[1;32mAlready paired!\e[0m Connected on port \e[1;33m$current_port\e[0m."
            echo ""
            echo -e "  [1] \e[1;32m(Recommended)\e[0m Continue with this connection"
            echo -e "  [2] Pair fresh (if connection seems wrong)"
            echo -e "  [3] Enter a different port manually"
            echo -ne "👉 \e[1;36mChoose 1, 2, or 3 (press Enter for 1): \e[0m"
            read auto_choice
            auto_choice=${auto_choice:-1}
            if ! [[ "$auto_choice" =~ ^[123]$ ]]; then
                echo "Choose 1, 2, or 3." >&2
                return 1
            fi

            if [[ "$auto_choice" == "2" ]] || [[ "$auto_choice" == "3" ]]; then
                _adbcon_timed disconnect "$IP:$current_port" >/dev/null 2>&1 || true
                auto_connected=0
                if [[ "$auto_choice" == "2" ]]; then
                    wizard_choice="2"
                else
                    wizard_choice="1"
                fi
                echo ""
            fi
        fi
    elif [ -z "$direct_port" ] && [ "$direct_pair" -eq 0 ]; then
        echo "Skipping port scan. Use 'adbcon --scan' to search for an already-paired port."
    fi

    if [ $auto_connected -eq 0 ]; then
        if [ -z "$wizard_choice" ] && [ -z "$direct_port" ]; then
            echo -e "⚠️  \e[33mCould not connect automatically — pairing may be needed.\e[0m\n"

            echo -e "\e[1;35m[ What would you like to do? ]\e[0m"
            echo -e "  [1] Enter connection port manually (already paired)"
            echo -e "  [2] \e[1;32m(Recommended)\e[0m Pair fresh (first time or re-pair)"
            echo -ne "👉 \e[1;36mChoose 1 or 2 (press Enter for 2): \e[0m"
            read wizard_choice
            wizard_choice=${wizard_choice:-2}
            if ! [[ "$wizard_choice" =~ ^[12]$ ]]; then
                echo "Choose 1 or 2." >&2
                return 1
            fi
            echo ""
        fi

        if [[ "$wizard_choice" == "2" ]]; then
            if [ -z "$pair_port" ] || [ -z "$pair_code" ]; then
                echo -e "\e[1;33m--- PAIRING MODE ---\e[0m"
                echo -e "💡 \e[1;33mTIP:\e[0m Use \e[1;37mSplit Screen\e[0m or \e[1;37mFloating Window\e[0m so you can see"
                echo -e "   the pairing popup and Termux at the same time.\n"
                echo -e "1. Tap on the words \e[1;37m'Wireless Debugging'\e[0m in settings to open its menu."
                echo -e "2. Tap \e[1;37m'Pair device with pairing code'\e[0m."
                echo -e "3. A popup will show a Wi-Fi pairing code and an address like \e[1;37m192.168.x.x:XXXXX\e[0m."
                echo ""
                echo -ne "👉 Enter the \e[1;31mPAIRING PORT\e[0m (e.g. 37123 or 192.168.x.x:37123): "
                read raw_pair_port
                echo -ne "👉 Enter the \e[1;32mPAIRING CODE\e[0m (6-digit code shown in the popup): "
                read pair_code

                if [ -z "$raw_pair_port" ] || [ -z "$pair_code" ]; then
                    echo -e "\e[1;31m❌ Cancelled.\e[0m"
                    return 1
                fi

                _adbcon_parse_endpoint "$raw_pair_port"
                if [ -n "$PARSED_IP" ] && _adbcon_valid_ipv4 "$PARSED_IP"; then
                    IP="$PARSED_IP"
                fi
                pair_port="$PARSED_PORT"

                if ! _adbcon_valid_port "$pair_port"; then
                    echo "Invalid pairing port: $pair_port"
                    return 1
                fi
                if ! _adbcon_valid_pair_code "$pair_code"; then
                    echo "Pairing code must contain exactly 6 digits."
                    return 1
                fi
            fi

            echo -e "\nPairing with $IP:$pair_port..."

            local pair_result pair_status
            pair_result=$(_adbcon_timed pair "$IP:$pair_port" "$pair_code" 2>&1)
            pair_status=$?

            if _adbcon_pair_succeeded "$pair_status" "$pair_result"; then
                echo -e "\e[1;32m✓ Pairing complete! Now we need to connect.\e[0m\n"
            else
                echo -e "\e[1;33m⚠️  First attempt failed, retrying with fresh server...\e[0m"
                _adbcon_timed kill-server > /dev/null 2>&1
                sleep 0.8
                _adbcon_timed start-server > /dev/null 2>&1
                sleep 0.4
                pair_result=$(_adbcon_timed pair "$IP:$pair_port" "$pair_code" 2>&1)
                pair_status=$?

                if _adbcon_pair_succeeded "$pair_status" "$pair_result"; then
                    echo -e "\e[1;32m✓ Pairing complete! Now we need to connect.\e[0m\n"
                else
                    echo -e "\e[1;31m❌ Pairing failed: ${pair_result:-ADB returned no error details.}\e[0m"
                    echo -e "Make sure the pairing popup is still open (it expires quickly)."
                    return 1
                fi
            fi
        fi

        # Manual connect (for option 1, direct port, or after pairing in option 2)
        if [ -z "$current_port" ]; then
            echo -e "\e[1;33m--- CONNECTION MODE ---\e[0m"
            echo -e "Look at the main \e[1;37mWireless Debugging\e[0m screen → \e[1;37m'IP address & Port'\e[0m section."
            echo -ne "👉 Enter the \e[1;34mCONNECTION PORT\e[0m (e.g. 42587 or 192.168.x.x:42587): "
            read raw_conn_port

            if [ -z "$raw_conn_port" ]; then
                echo -e "\e[1;31m❌ Cancelled.\e[0m"
                return 1
            fi

            _adbcon_parse_endpoint "$raw_conn_port"
            if [ -n "$PARSED_IP" ] && _adbcon_valid_ipv4 "$PARSED_IP"; then
                IP="$PARSED_IP"
            fi
            current_port="$PARSED_PORT"

            if ! _adbcon_valid_port "$current_port"; then
                echo "Invalid connection port: $current_port"
                return 1
            fi
        fi

        echo -e "Connecting to $IP:$current_port..."
        _adbcon_timed connect "$IP:$current_port" 2>&1

        # Give ADB time to complete TCP handshake
        local connect_ok=0
        for i in {1..3}; do
            sleep 0.5
            local dev_line
            dev_line=$(_adbcon_timed devices 2>/dev/null | grep -F "${IP}:${current_port}")
            if echo "$dev_line" | grep -qE "[[:space:]]device([[:space:]]|$)"; then
                connect_ok=1
                break
            elif echo "$dev_line" | grep -q "unauthorized"; then
                echo -e "\e[1;33m🔒 Connected but unauthorized — pairing was revoked or the phone doesn't recognise this Termux.\e[0m"
                echo -e "   Re-run \`adbcon\` and pick fresh-pair mode."
                _adbcon_timed disconnect "$IP:$current_port" > /dev/null 2>&1
                return 1
            fi
            echo "Waiting for device to come online (attempt $i/3)..."
        done

        if [ $connect_ok -eq 0 ]; then
            # One final reconnect attempt
            _adbcon_timed disconnect "$IP:$current_port" > /dev/null 2>&1
            _adbcon_timed connect "$IP:$current_port" > /dev/null 2>&1
            sleep 0.8
        fi
    fi

    if _adbcon_timed devices 2>/dev/null | grep -q "${IP}:${current_port}[[:space:]]*device"; then
        echo -e "\n🎉 \e[1;32mConnection successful!\e[0m"
        echo -e "🔄 \e[1;36mLocking into offline loopback mode (port 5555)...\e[0m"
        _adbcon_timed tcpip 5555 > /dev/null 2>&1

        # Quick loopback lock
        local loopback_success=0
        for i in {1..6}; do
            sleep 0.5
            _adbcon_timed connect "$LOCAL_LOOPBACK" > /dev/null 2>&1 || true
            if _adbcon_timed devices 2>/dev/null | grep -q "${LOCAL_LOOPBACK}[[:space:]]*device"; then
                loopback_success=1
                break
            fi
        done

        if [ $loopback_success -eq 1 ]; then
            _adbcon_timed disconnect "$IP:$current_port" > /dev/null 2>&1 || true
            _adbcon_timed -s "$LOCAL_LOOPBACK" wait-for-device 2>/dev/null
            echo -e "🚀 \e[1;32mEverything set up! Loopback mode is active.\e[0m\n"
            _adbcon_cache_save "$IP:$current_port"
            if [ "$no_shell" -eq 1 ]; then
                return 0
            fi
            echo -e "Dropping into loopback shell...\n"
            adb -s "$LOCAL_LOOPBACK" shell
            return $?
        else
            echo -e "⚠️  \e[33mFailed to lock loopback channel (port 5555).\e[0m"
            echo -e "🚀 \e[1;32mFalling back to active Wi-Fi channel.\e[0m\n"
            _adbcon_cache_save "$IP:$current_port"
            _adbcon_timed -s "$IP:$current_port" wait-for-device 2>/dev/null
            if [ "$no_shell" -eq 1 ]; then
                return 0
            fi
            echo -e "Dropping into shell...\n"
            adb -s "$IP:$current_port" shell
            return $?
        fi
    else
        echo -e "\e[1;31m❌ Connection failed.\e[0m"
        echo "Make sure the Port exactly matches the 'IP address & Port' section."
        return 1
    fi
}
