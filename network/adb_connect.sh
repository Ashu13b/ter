#!/bin/bash

adbcon() {
    local LOCAL_LOOPBACK="127.0.0.1:5555"

    # --- FLAG HANDLING SECTION ---
    if [[ "$1" == "-d" ]] || [[ "$1" == "--exit" ]] || [[ "$1" == "disconnect" ]]; then
        echo "========================================"
        echo "       ADB CLEANUP & DISCONNECT         "
        echo "========================================"
        echo "🔌 Disconnecting all active ADB sessions..."
        adb disconnect > /dev/null 2>&1
        
        echo "🛑 Stopping background ADB server daemon..."
        adb kill-server > /dev/null 2>&1
        
        echo "✨ Cleaned up successfully. ADB is completely offline."
        echo "========================================"
        return 0
    fi

    # --- NORMAL CONNECTION LOGIC ---
    echo "========================================"
    echo "      TERMUX ADB SMART ASSISTANT        "
    echo "========================================"

    echo "Checking persistent background channel..."
    adb connect $LOCAL_LOOPBACK > /dev/null 2>&1

    if adb devices | grep -q "${LOCAL_LOOPBACK}[[:space:]]*device"; then
        echo "🎉 Connection alive! Bypassing Wi-Fi network completely."
        echo "Entering shell..."
        echo "----------------------------------------"
        adb -s "$LOCAL_LOOPBACK" shell
        return 0
    fi

    echo "⚠️  Background channel is offline (phone rebooted or reset)."
    echo "----------------------------------------"
    echo "Select connection method:"
    echo " [1] Automatic Scan (Fast port discovery - no typing)"
    echo " [2] Manual Port (Enter port shown on phone screen)"
    echo -n "👉 Choose option (1 or 2, default is 1): "
    read connect_choice
    connect_choice=${connect_choice:-1}
    echo "----------------------------------------"

    # Detect all local IP addresses (excluding localhost)
    local IPS=$(ifconfig 2>/dev/null | grep -oE 'inet (addr:)?[0-9.]+' | grep -oE '[0-9.]+' | grep -v '127.0.0.1')

    # Setup common fallback IP detection
    local DETECTED_IP=$(echo "$IPS" | head -n 1)

    if [[ "$connect_choice" == "1" ]]; then
        echo "ℹ️  Prerequisites for automatic connection:"
        echo "  1. Ensure your phone is connected to any Wi-Fi or Hotspot."
        echo "  2. Go to Settings -> Developer Options -> Wireless Debugging and turn it ON."
        echo "----------------------------------------"
        echo "🔍 Scanning local network interfaces to automatically discover the random port..."
        
        if [ -n "$IPS" ]; then
            for ip in $IPS; do
                echo "📡 Scanning interface IP $ip for Wireless Debugging port..."
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
' "$ip" 2>/dev/null)

                for port in $ports; do
                    echo "🔌 Found active port $port. Attempting handshake..."
                    adb connect "$ip:$port" > /dev/null 2>&1
                    sleep 0.5
                    
                    if adb devices | grep -q "${ip}:${port}[[:space:]]*device"; then
                        echo "🎉 Connection successful! Connected to $ip:$port"
                        echo "🔄 Routing ADB to local background port 5555..."
                        adb -s "$ip:$port" tcpip 5555 > /dev/null 2>&1
                        sleep 1.5
                        
                        adb connect $LOCAL_LOOPBACK > /dev/null 2>&1
                        sleep 0.5
                        
                        adb disconnect "$ip:$port" > /dev/null 2>&1
                        
                        if adb devices | grep -q "$LOCAL_LOOPBACK[[:space:]]*device"; then
                            echo "🚀 Offline loopback activated! Dropping into shell..."
                            echo "========================================"
                            adb -s "$LOCAL_LOOPBACK" shell
                            return 0
                        fi
                    else
                        adb disconnect "$ip:$port" > /dev/null 2>&1
                    fi
                done
            done
        fi
        echo "❌ Could not auto-detect or connect to any active Wireless Debugging ports."
        echo "Falling back to manual setup..."
        echo "----------------------------------------"
    fi

    # Manual connection flow (either chosen directly, or fallback from failed scan)
    if [ -z "$DETECTED_IP" ]; then
        echo -n "👉 Please manually enter your phone's IP address: "
        read DETECTED_IP
    else
        echo "📱 Detected IP address: $DETECTED_IP"
        echo -n "👉 Is this correct? (Y/n): "
        read confirm_ip
        if [[ "$confirm_ip" =~ ^[Nn]$ ]]; then
            echo -n "👉 Enter the correct IP address: "
            read DETECTED_IP
        fi
    fi

    if [ -z "$DETECTED_IP" ]; then
        echo "❌ IP address is required."
        return 1
    fi

    echo "----------------------------------------"
    echo -n "❓ Do you need to PAIR this device first? (y/N): "
    read pair_choice
    if [[ "$pair_choice" =~ ^[Yy]$ ]]; then
        echo "----------------------------------------"
        echo "1. Go to Settings -> Developer Options -> Wireless Debugging."
        echo "2. Tap 'Pair device with pairing code'."
        echo "----------------------------------------"
        local pair_port
        local pair_code
        echo -n "👉 Enter the 5-digit PAIRING PORT: "
        read pair_port
        echo -n "👉 Enter the 6-digit PAIRING CODE: "
        read pair_code
        
        if [ -z "$pair_port" ] || [ -z "$pair_code" ]; then
            echo "❌ Pairing cancelled (missing details)."
            return 1
        fi
        
        echo "Pairing with $DETECTED_IP:$pair_port..."
        adb pair "$DETECTED_IP:$pair_port" "$pair_code"
        echo "----------------------------------------"
    fi

    local current_port
    echo -n "👉 Enter the CONNECTION PORT (shown under 'IP address & Port'): "
    read current_port

    if [ -z "$current_port" ]; then
        echo "❌ Connection cancelled. Missing port input."
        return 1
    fi

    echo "----------------------------------------"
    echo "Connecting to $DETECTED_IP:$current_port..."
    adb connect "$DETECTED_IP:$current_port"

    if adb devices | grep -q "${DETECTED_IP}:${current_port}[[:space:]]*device"; then
        echo "🔄 Success! Routing ADB to local background port 5555..."
        adb tcpip 5555
        sleep 1.5
        
        echo "🔌 Locking into offline mode..."
        adb connect $LOCAL_LOOPBACK
        
        echo "🚀 Everything set up! Dropping into shell..."
        echo "========================================"
        adb -s "$LOCAL_LOOPBACK" shell
    else
        echo "❌ Connection failed."
        echo "Please verify that the Port matches the screen exactly and your phone trusts Termux."
    fi
}
