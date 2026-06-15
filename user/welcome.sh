welcome() {
    local user_name="${MY_NAME:-Operator}"
    local upper_name; [ "$CURRENT_SHELL" = "zsh" ] && upper_name="${(U)user_name}" || upper_name="${user_name^^}"
    local ip; ip=$(get_lan_ip)
    local dt; dt=$(date "+%Y-%m-%d %H:%M")
    local app_count=0
    if [ -d "$HOME/.shell.d/apps" ]; then
        for d in "$HOME/.shell.d/apps"/*/; do
            [ -d "$d" ] && ((app_count++))
        done
    fi

    echo -e "\n${C_MAGENTA}───${C_RESET}  ${C_BOLD}${C_CYAN}TER OS${C_RESET} ${C_DIM}v${TER_VERSION:-1.1}${C_RESET}  ${C_MAGENTA}────────────────────────────────────────${C_RESET}"
    echo -e "  ${C_BOLD}WELCOME, ${C_YELLOW}${upper_name}${C_RESET}"
    echo -e "  ${C_DIM}IP:${C_RESET} ${C_GREEN}${ip}${C_RESET}  ${C_DIM}|  Time:${C_RESET} ${C_BLUE}${dt}${C_RESET}  ${C_DIM}|  Apps:${C_RESET} ${C_CYAN}${app_count}${C_RESET}"
    echo -e "${C_MAGENTA}────────────────────────────────────────────────────────────${C_RESET}"
    
    local tips=("apps list → View registered apps." "adbcon → Connect ADB wirelessly." "scan net → Find devices." "optimize status → Audit background stability.")
    echo -e "  ${C_YELLOW}💡${C_RESET}  ${C_DIM}${tips[$(( RANDOM % 4 ))]}${C_RESET}"
    echo -e "${C_MAGENTA}────────────────────────────────────────────────────────────${C_RESET}"
    
    echo -e "  ${C_BOLD}${C_BLUE}▰▰▰ SYSTEM OPERATIONS${C_RESET}"
    printf "  ${C_CYAN}%-10s${C_RESET} [%s] Reload   [%s] Update   [%s] Clear\\n" "SYSTEM" "re" "up" "cls"
    printf "  ${C_CYAN}%-10s${C_RESET} [%s] Back     [%s] Up 2     [%s] Home\\n" "NAV" ".." "..." "cd"
    printf "  ${C_CYAN}%-10s${C_RESET} [%s] Workspace[%s] Download [%s] Storage\\n" "DIRS" "cd ws" "cd dl" "storage"
    printf "  ${C_CYAN}%-10s${C_RESET} [%s] ADB con  [%s] Net Scan [%s] App List\\n" "TOOLS" "adbcon" "scan net" "apps list"
    printf "  ${C_CYAN}%-10s${C_RESET} [%s] BG Audit [%s] BG Fix    [%s] Task List\\n" "STABILITY" "optimize status" "optimize fix" "optimize list"
    
    # Load app welcome contributions
    local has_apps=0
    for _wf in "$HOME/.shell.d/apps"/*/welcome.hook; do
        if [ -f "$_wf" ]; then
            if [ $has_apps -eq 0 ]; then
                echo -e "${C_MAGENTA}────────────────────────────────────────────────────────────${C_RESET}"
                echo -e "  ${C_BOLD}${C_CYAN}▰▰▰ REGISTERED APPLICATIONS${C_RESET}"
                has_apps=1
            fi
            source "$_wf"
        fi
    done
    unset _wf
    echo -e "${C_MAGENTA}────────────────────────────────────────────────────────────${C_RESET}\n"
}
