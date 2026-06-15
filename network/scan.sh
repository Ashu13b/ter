# ── Network Security Auditor (Engineer Edition) ──

# Helper: Find the real local subnet
_scan_get_subnet() {
    python3 -c "
import subprocess, re
try:
    out = subprocess.check_output(['ifconfig'], stderr=subprocess.STDOUT).decode()
    matches = re.findall(r'inet\s+(10\.\d+\.\d+\.\d+|172\.(?:1[6-9]|2\d|3[0-1])\.\d+\.\d+|192\.168\.\d+\.\d+)', out)
    if matches:
        print('.'.join(matches[0].split('.')[:-1]) + '.0/24')
    else:
        print('10.225.222.0/24')
except:
    print('10.225.222.0/24')
" 2>/dev/null
}

scan() {
    if [[ -z "$1" ]] || [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]] || [[ "$1" == "help" ]]; then
        echo -e "${C_BOLD}${C_CYAN}─── NETWORK SECURITY AUDITOR HELP ───${C_RESET}"
        echo "Usage: scan <command> [target]"
        echo ""
        echo "Commands:"
        echo "  net          Scan the local network subnet to discover active hosts/devices"
        echo "  sniff        Check a target IP for open plain-text protocols (FTP, Telnet, HTTP, POP3)"
        echo "  vuln         Audit a target IP for common open service ports (SSH, ADB, VNC, HTTP-Alt)"
        echo ""
        return 0
    fi

    local cmd="$1"
    local target="$2"
    local subnet=$(_scan_get_subnet)

    case "$cmd" in
        "net")
            style_header "DEVICE DISCOVERY ($subnet)"
            echo -e "${C_CYAN}[ACTION]${C_RESET} Probing all nodes..."
            local res=$(nmap -Pn -p 22,80,443,8080,8082 -T4 --max-rtt-timeout 200ms "$subnet" | grep "Nmap scan report" | awk '{print $NF}' | tr -d '()')
            if [ -n "$res" ]; then
                echo -e "${C_YELLOW}Detected Nodes:${C_RESET}"
                echo "$res" | grep -v "127.0.0.1"
            else
                echo -e "${C_RED}No nodes found.${C_RESET}"
            fi
            ;;
        "sniff")
            [ -z "$target" ] && { echo "Usage: scan sniff <ip>"; return 1; }
            style_header "SECURITY CHECK ($target)"
            local v=$(nmap -Pn -p 21,23,80,110 --open "$target" | grep "open")
            if [ -n "$v" ]; then
                echo -e "${C_RED}⚠ PLAIN-TEXT LEAK FOUND!${C_RESET}"
                echo "$v"
            else
                echo -e "${C_GREEN}✓ SECURE${C_RESET}"
            fi
            ;;
        "vuln")
            [ -z "$target" ] && { echo "Usage: scan vuln <ip>"; return 1; }
            style_header "VULNERABILITY AUDIT ($target)"
            echo -e "${C_CYAN}[ACTION]${C_RESET} Auditing common risk ports (22, 5555, 5900, 8080)..."
            local res=$(nmap -Pn -p 22,5555,5900,8080 --open "$target" | grep "open")
            if [ -n "$res" ]; then
                echo -e "${C_RED}⚠️ POTENTIALLY EXPOSED SERVICES FOUND:${C_RESET}"
                echo "$res" | sed 's/^/  /'
            else
                echo -e "${C_GREEN}✓ No common risk services exposed.${C_RESET}"
            fi
            ;;
        *)
            echo -e "${C_RED}❌ Unknown command: $cmd${C_RESET}"
            echo "Usage: scan net | sniff <ip> | vuln <ip>"
            return 1
            ;;
    esac
}
