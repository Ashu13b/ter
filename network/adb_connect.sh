#!/bin/bash

adbcon() {
    local LOCAL_LOOPBACK="127.0.0.1:5555"

    if [[ "$1" == "-d" ]] || [[ "$1" == "--exit" ]] || [[ "$1" == "disconnect" ]]; then
        echo -e "\e[1;34m[ ADB DISCONNECT ]\e[0m"
        adb disconnect > /dev/null 2>&1
        adb kill-server > /dev/null 2>&1
        echo "✨ ADB is completely offline."
        return 0
    fi

    if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
        echo "========================================"
        echo "    ADB CONNECTION MODULE GUIDE         "
        echo "========================================"
        echo "Usage: adbcon [option]"
        echo ""
        echo "Options:"
        echo "  adbcon                     Launch Smart ADB connection wizard"
        echo "  adbcon -d, --exit          Disconnect and kill the active ADB server"
        echo "  adbcon -h, --help          Show this connection help manual"
        echo "========================================"
        return 0
    fi

    echo -e "\n\e[1;36m══ TERMUX SMART ADB WIZARD ══\e[0m\n"

    # 1. Fast check for existing loopback
    adb connect $LOCAL_LOOPBACK > /dev/null 2>&1
    sleep 0.5
    if adb devices | grep -q "${LOCAL_LOOPBACK}[[:space:]]*device"; then
        echo -e "🎉 \e[1;32mConnection is alive and locked in background!\e[0m"
        echo -e "Dropping into shell...\n"
        adb -s "$LOCAL_LOOPBACK" shell
        return 0
    fi

    # Clean up stale loopback entry so it doesn't interfere
    adb disconnect $LOCAL_LOOPBACK > /dev/null 2>&1

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
        IP=$(ip addr 2>/dev/null | grep -oP 'inet \K[0-9.]+' | grep -v '127.0.0.1' | head -n 1)
        if [ -z "$IP" ]; then
            IP="192.168.1.1"
            echo -e "⚠️  \e[33mNo Wi-Fi detected automatically — using fallback $IP.\e[0m"
        else
            echo -e "📡 \e[1;32mNetwork detected:\e[0m $IP"
        fi
    fi

    echo -ne "👉 Phone IP [\e[1;33m$IP\e[0m] — press Enter to use this, or type a different IP: "
    read input_ip
    local ORIG_IP="$IP"
    IP=${input_ip:-$IP}

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

    echo -e "\n\e[1;35m[ REQUIRED PREPARATION ]\e[0m"
    echo -e "1. Go to phone \e[1;37mSettings\e[0m -> \e[1;37mDeveloper Options\e[0m."
    echo -e "2. Scroll down to \e[1;37mWireless Debugging\e[0m and turn it \e[1;32mON\e[0m."
    echo -e "   (If it asks to allow the network, click Allow/Always Allow)\n"

    # 3. Auto-detect: try to find an open Wireless Debugging port
    echo -e "🔍 \e[1;36mChecking if already paired (scanning for open port)...\e[0m"
    local ports=$(python3 -c '
import socket, sys, concurrent.futures
ip = sys.argv[1]
def scan(p):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(0.06)
        if s.connect_ex((ip, p)) == 0:
            return p
    return None
with concurrent.futures.ThreadPoolExecutor(max_workers=250) as e:
    results = e.map(lambda p: scan(p), range(30000, 50000))
    for r in results:
        if r: print(r)
' "$IP" 2>/dev/null)

    local auto_connected=0
    local current_port=""
    local pairing_revoked=0
    for port in $ports; do
        echo -e "🔌 Found port \e[1;33m$port\e[0m. Testing connection..."
        adb connect "$IP:$port" > /dev/null 2>&1
        sleep 0.5
        local dev_line
        dev_line=$(adb devices | grep "${IP}:${port}")
        if echo "$dev_line" | grep -q "device$"; then
            auto_connected=1
            current_port=$port
            break
        elif echo "$dev_line" | grep -q "unauthorized"; then
            # Pairing revoked/expired — retrying other ports on the same phone won't help.
            echo -e "🔒 \e[1;33mPort $port is open but the pairing is no longer trusted.\e[0m"
            adb disconnect "$IP:$port" > /dev/null 2>&1
            pairing_revoked=1
            break
        else
            adb disconnect "$IP:$port" > /dev/null 2>&1
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

        if [[ "$auto_choice" == "2" ]] || [[ "$auto_choice" == "3" ]]; then
            adb disconnect "$IP:$current_port" > /dev/null 2>&1
            auto_connected=0
            if [[ "$auto_choice" == "2" ]]; then
                wizard_choice="2"
            else
                wizard_choice="1"
            fi
            echo ""
        fi
    fi

    if [ $auto_connected -eq 0 ]; then
        if [ -z "$wizard_choice" ]; then
            echo -e "⚠️  \e[33mCould not connect automatically — pairing may be needed.\e[0m\n"

            echo -e "\e[1;35m[ What would you like to do? ]\e[0m"
            echo -e "  [1] Enter connection port manually (already paired)"
            echo -e "  [2] \e[1;32m(Recommended)\e[0m Pair fresh (first time or re-pair)"
            echo -ne "👉 \e[1;36mChoose 1 or 2 (press Enter for 2): \e[0m"
            read wizard_choice
            wizard_choice=${wizard_choice:-2}
            echo ""
        fi

        if [[ "$wizard_choice" == "2" ]]; then
            echo -e "\e[1;33m--- PAIRING MODE ---\e[0m"
            echo -e "💡 \e[1;33mTIP:\e[0m Use \e[1;37mSplit Screen\e[0m or \e[1;37mFloating Window\e[0m so you can see"
            echo -e "   the pairing popup and Termux at the same time.\n"
            echo -e "1. Tap on the words \e[1;37m'Wireless Debugging'\e[0m in settings to open its menu."
            echo -e "2. Tap \e[1;37m'Pair device with pairing code'\e[0m."
            echo -e "3. A popup will show a Wi-Fi pairing code and an address like \e[1;37m192.168.x.x:XXXXX\e[0m."
            echo ""
            echo -ne "👉 Enter the \e[1;31mPAIRING PORT\e[0m (number after ':' in the popup, e.g. 37123): "
            read pair_port
            echo -ne "👉 Enter the \e[1;32mPAIRING CODE\e[0m (6-digit code shown in the popup): "
            read pair_code

            if [ -z "$pair_port" ] || [ -z "$pair_code" ]; then
                echo -e "\e[1;31m❌ Cancelled.\e[0m"
                return 1
            fi

            echo -e "\nPairing with $IP:$pair_port..."

            # Kill stale server to prevent 'protocol fault' errors
            adb kill-server > /dev/null 2>&1
            sleep 0.5
            adb start-server > /dev/null 2>&1

            local pair_result
            pair_result=$(adb pair "$IP:$pair_port" "$pair_code" 2>&1)

            if echo "$pair_result" | grep -qi "success\|paired"; then
                echo -e "\e[1;32m✓ Pairing complete! Now we need to connect.\e[0m\n"
            else
                echo -e "\e[1;33m⚠️  First attempt failed, retrying with fresh server...\e[0m"
                adb kill-server > /dev/null 2>&1
                sleep 1
                adb start-server > /dev/null 2>&1
                sleep 0.5
                pair_result=$(adb pair "$IP:$pair_port" "$pair_code" 2>&1)

                if echo "$pair_result" | grep -qi "success\|paired"; then
                    echo -e "\e[1;32m✓ Pairing complete! Now we need to connect.\e[0m\n"
                else
                    echo -e "\e[1;31m❌ Pairing failed: $pair_result\e[0m"
                    echo -e "Make sure the pairing popup is still open (it expires quickly)."
                    return 1
                fi
            fi
        fi

        # Manual connect (for both option 1 and after pairing in option 2)
        echo -e "\e[1;33m--- CONNECTION MODE ---\e[0m"
        echo -e "Look at the main \e[1;37mWireless Debugging\e[0m screen → \e[1;37m'IP address & Port'\e[0m section."
        echo -ne "👉 Enter the \e[1;34mCONNECTION PORT\e[0m (number after ':', e.g. 42587): "
        read current_port

        if [ -z "$current_port" ]; then
            echo -e "\e[1;31m❌ Cancelled.\e[0m"
            return 1
        fi

        echo -e "Connecting to $IP:$current_port..."
        adb connect "$IP:$current_port" 2>&1

        # Give ADB time to complete the TCP handshake
        local connect_ok=0
        for i in {1..3}; do
            sleep 1
            local dev_line
            dev_line=$(adb devices | grep "${IP}:${current_port}")
            if echo "$dev_line" | grep -q "device$"; then
                connect_ok=1
                break
            elif echo "$dev_line" | grep -q "unauthorized"; then
                echo -e "\e[1;33m🔒 Connected but unauthorized — pairing was revoked or the phone doesn't recognise this Termux.\e[0m"
                echo -e "   Re-run \`adbcon\` and pick fresh-pair mode."
                adb disconnect "$IP:$current_port" > /dev/null 2>&1
                return 1
            fi
            echo "Waiting for device to come online (attempt $i/3)..."
        done

        if [ $connect_ok -eq 0 ]; then
            # One final reconnect attempt in case the first was a stale server
            adb disconnect "$IP:$current_port" > /dev/null 2>&1
            adb connect "$IP:$current_port" > /dev/null 2>&1
            sleep 1.5
        fi
    fi




    if adb devices | grep -q "${IP}:${current_port}[[:space:]]*device"; then
        echo -e "\n🎉 \e[1;32mConnection successful!\e[0m"
        echo -e "🔄 \e[1;36mLocking into offline loopback mode (port 5555)...\e[0m"
        adb tcpip 5555 > /dev/null 2>&1

        # adbd restarts after tcpip — wait for it to come back
        sleep 2

        local loopback_success=0
        for i in {1..5}; do
            echo "Attempting to connect to loopback channel (try $i/5)..."
            adb connect $LOCAL_LOOPBACK > /dev/null 2>&1
            sleep 1.5
            if adb devices | grep -q "${LOCAL_LOOPBACK}[[:space:]]*device"; then
                loopback_success=1
                break
            fi
        done

        if [ $loopback_success -eq 1 ]; then
            adb disconnect "$IP:$current_port" > /dev/null 2>&1
            # Wait for device to be fully ready (not just listed)
            echo "Waiting for device to be ready..."
            adb -s "$LOCAL_LOOPBACK" wait-for-device 2>/dev/null
            sleep 1
            echo -e "🚀 \e[1;32mEverything set up! Dropping into loopback shell...\e[0m\n"
            adb -s "$LOCAL_LOOPBACK" shell
        else
            echo -e "⚠️  \e[33mFailed to lock loopback channel (port 5555).\e[0m"
            echo -e "🚀 \e[1;32mFalling back to active Wi-Fi channel. Dropping into shell...\e[0m\n"
            adb -s "$IP:$current_port" wait-for-device 2>/dev/null
            adb -s "$IP:$current_port" shell
        fi
    else
        echo -e "\e[1;31m❌ Connection failed.\e[0m"
        echo "Make sure the Port exactly matches the 'IP address & Port' section."
    fi
}
