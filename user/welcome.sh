welcome() {
    local user_name="${MY_NAME:-Operator}"
    local upper_name; [ "$CURRENT_SHELL" = "zsh" ] && upper_name="${(U)user_name}" || upper_name="${user_name^^}"
    local c_m="${C_CYAN}"; local c_s="${C_BLUE}"; local c_a="${C_MAGENTA}"
    echo -e "\n${c_m}    /\\ ${c_s}  TERMUX OS ${C_DIM}v1.0${C_RESET}\n   /  \\  ────────────────────\n  /____\\ ${c_a}WELCOME, ${C_BOLD}${upper_name}${C_RESET}\n"
    local tips=("apps list → View registered apps." "adbcon → Connect ADB wirelessly." "scan net → Find devices.")
    echo -e "  ${C_YELLOW}INTELLIGENCE:${C_RESET} ${C_DIM}${tips[$(( RANDOM % 3 ))]}${C_RESET}"
    echo -e "\n  ${C_DIM}▰▰▰ OPERATIONS MATRIX ▰▰▰${C_RESET}"
    printf "  ${c_m}%-10s${C_RESET} [%s] Reload  [%s] Update   [%s] Clear\n" "SYSTEM" "re" "up" "c"
    printf "  ${c_m}%-10s${C_RESET} [%s] Back    [%s] Up 2     [%s] Home\n" "NAV" ".." "..." "h"
    printf "  ${c_m}%-10s${C_RESET} [%s] Code    [%s] Download [%s] Android\n" "DIRS" "ws" "dl" "storage"
    printf "  ${c_m}%-10s${C_RESET} [%s] ADB     [%s] Scan     [%s] Apps\n" "TOOLS" "adbcon" "scan net" "apps list"
    # Load app welcome contributions
    for _wf in "$HOME/.shell.d/apps"/*/welcome.hook; do
        [ -f "$_wf" ] && source "$_wf"
    done
    unset _wf
    echo ""
}
