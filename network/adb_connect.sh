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
    if adb devices | grep -q "${LOCAL_LOOPBACK}[[:space:]]*device"; then
        echo -e "🎉 \e[1;32mConnection is alive and locked in background!\e[0m"
        echo -e "Dropping into shell...\n"
        adb -s "$LOCAL_LOOPBACK" shell
        return 0
    fi

    echo -e "⚠️  \e[33mBackground channel offline (Phone rebooted or ADB killed)\e[0m\n"

    # 2. Check Network (Required for Wireless Debugging)
    local IP
    IP=$(ifconfig 2>/dev/null | grep -oE 'inet (addr:)?[0-9.]+' | grep -oE '[0-9.]+' | grep -v '127.0.0.1' | head -n 1)

    if [ -z "$IP" ]; then
        echo -e "\e[1;31m[!] No Wi-Fi or Hotspot detected.\e[0m"
        echo -e "Android requires a network connection to activate Wireless Debugging."
        echo -e "👉 \e[1;37mACTION:\e[0m Please connect to any Wi-Fi network or enable Hotspot, then run \e[1;32madbcon\e[0m again."
        return 1
    fi

    echo -e "📡 \e[1;32mNetwork detected:\e[0m IP address is $IP\n"

    # 3. Wizard Guide
    echo -e "\e[1;35m[ STEP 1: Enable Developer Options ]\e[0m"
    echo -e "1. Go to phone \e[1;37mSettings\e[0m -> \e[1;37mDeveloper Options\e[0m."
    echo -e "2. Scroll down to \e[1;37mWireless Debugging\e[0m and turn it \e[1;32mON\e[0m."
    echo -e "   (If it asks to allow the network, click Allow/Always Allow)\n"

    echo -e "\e[1;35m[ STEP 2: Pairing Status ]\e[0m"
    echo -e "Have you ever paired Termux with this phone before?"
    echo -e "  [1] Yes, already paired before (Connect only)"
    echo -e "  [2] No, first time on this phone (Pair & Connect)"
    echo -e "  [3] Auto-scan (Try to find port automatically if already paired)"
    echo -ne "👉 \e[1;36mChoose (1, 2, or 3) [Default 3]: \e[0m"
    read wizard_choice
    wizard_choice=${wizard_choice:-3}

    echo ""

    if [[ "$wizard_choice" == "2" ]]; then
        echo -e "\e[1;33m--- PAIRING MODE ---\e[0m"
        echo -e "1. Tap on the words \e[1;37m'Wireless Debugging'\e[0m in settings to open its menu."
        echo -e "2. Tap \e[1;37m'Pair device with pairing code'\e[0m."
        echo -e "3. A popup will show a 6-digit Wi-Fi pairing code and an IP address & Port."
        echo ""
        echo -ne "👉 Enter the 5-digit \e[1;31mPAIRING PORT\e[0m (the number after the colon ':'): "
        read pair_port
        echo -ne "👉 Enter the 6-digit \e[1;32mPAIRING CODE\e[0m: "
        read pair_code

        if [ -z "$pair_port" ] || [ -z "$pair_code" ]; then
            echo -e "\e[1;31m❌ Cancelled.\e[0m"
            return 1
        fi

        echo -e "\nPairing with $IP:$pair_port..."
        adb pair "$IP:$pair_port" "$pair_code"
        echo -e "\e[1;32m✓ Pairing complete! Now we need to connect.\e[0m\n"
    fi

    if [[ "$wizard_choice" == "3" ]]; then
        echo -e "🔍 \e[1;36mScanning network for Wireless Debugging port...\e[0m"
        local ports=$(python3 -c '
import socket, sys, concurrent.futures
ip = sys.argv[1]
def scan(p):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(0.015)
        if s.connect_ex((ip, p)) == 0:
            return p
    return None
with concurrent.futures.ThreadPoolExecutor(max_workers=250) as e:
    results = e.map(lambda p: scan(p), range(30000, 50000))
    for r in results:
        if r: print(r)
' "$IP" 2>/dev/null)
        
        local success=0
        for port in $ports; do
            echo -e "🔌 Found port \e[1;33m$port\e[0m. Testing connection..."
            adb connect "$IP:$port" > /dev/null 2>&1
            sleep 0.5
            if adb devices | grep -q "${IP}:${port}[[:space:]]*device"; then
                success=1
                current_port=$port
                break
            else
                adb disconnect "$IP:$port" > /dev/null 2>&1
            fi
        done

        if [ $success -eq 0 ]; then
            echo -e "\e[1;31m❌ Auto-scan failed to connect.\e[0m"
            echo -e "Please ensure Wireless Debugging is ON and Termux is paired."
            wizard_choice="1" # Fallback to manual connect
            echo ""
        fi
    fi

    if [[ "$wizard_choice" == "1" ]] || [[ "$wizard_choice" == "2" ]]; then
        echo -e "\e[1;33m--- CONNECTION MODE ---\e[0m"
        echo -e "Look at the main Wireless Debugging screen (under 'IP address & Port')."
        echo -ne "👉 Enter the 5-digit \e[1;34mCONNECTION PORT\e[0m (the number after the colon ':'): "
        read current_port

        if [ -z "$current_port" ]; then
            echo -e "\e[1;31m❌ Cancelled.\e[0m"
            return 1
        fi

        echo -e "Connecting to $IP:$current_port..."
        adb connect "$IP:$current_port"
    fi

    if adb devices | grep -q "${IP}:${current_port}[[:space:]]*device"; then
        echo -e "\n🎉 \e[1;32mConnection successful!\e[0m"
        echo -e "🔄 \e[1;36mLocking into offline loopback mode (port 5555)...\e[0m"
        adb tcpip 5555 > /dev/null 2>&1
        sleep 1.5
        
        adb connect $LOCAL_LOOPBACK > /dev/null 2>&1
        sleep 0.5
        adb disconnect "$IP:$current_port" > /dev/null 2>&1

        echo -e "🚀 \e[1;32mEverything set up! Dropping into shell...\e[0m\n"
        adb -s "$LOCAL_LOOPBACK" shell
    else
        echo -e "\e[1;31m❌ Connection failed.\e[0m"
        echo "Make sure the Port exactly matches the 'IP address & Port' section."
    fi
}
