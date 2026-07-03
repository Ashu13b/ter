welcome() {
    local user_name="${MY_NAME:-Operator}"
    local upper_name; upper_name=$(printf '%s' "$user_name" | tr '[:lower:]' '[:upper:]')
    local ip; ip=$(get_lan_ip)
    local dt; dt=$(date "+%Y-%m-%d %H:%M")
    local app_count=0
    if [ -d "$HOME/.shell.d/apps" ]; then
        for d in "$HOME/.shell.d/apps"/*/; do
            [ -d "$d" ] && ((app_count++))
        done
    fi

    local RULE="${C_MAGENTA}────────────────────────────────────────────────────────────${C_RESET}"
    local ter_manifest="$HOME/.shell.d/manifest.json"
    local ter_ver="${TER_VERSION:-1.4}"
    if [ -f "$ter_manifest" ] && command -v jq >/dev/null 2>&1; then
        ter_ver=$(jq -r '.version // "1.4"' "$ter_manifest" 2>/dev/null)
    fi

    echo -e "\n${C_MAGENTA}───${C_RESET}  ${C_BOLD}${C_CYAN}TER OS${C_RESET} ${C_DIM}v${ter_ver}${C_RESET}  ${C_MAGENTA}────────────────────────────────────────${C_RESET}"
    echo -e "  ${C_BOLD}WELCOME, ${C_YELLOW}${upper_name}${C_RESET}"
    echo -e "  ${C_DIM}IP:${C_RESET} ${C_GREEN}${ip}${C_RESET}  ${C_DIM}|  Time:${C_RESET} ${C_BLUE}${dt}${C_RESET}  ${C_DIM}|  Apps:${C_RESET} ${C_CYAN}${app_count}${C_RESET}"
    echo -e "$RULE"

    # ── TER command surface — driven by ~/.shell.d/manifest.json ──
    # Add a new command by editing manifest.json's command_groups; welcome
    # picks it up automatically on the next new shell. No code change here.
    if [ -f "$ter_manifest" ] && command -v jq >/dev/null 2>&1; then
        echo -e "  ${C_BOLD}${C_BLUE}▰▰▰ TER COMMANDS${C_RESET}"
        while IFS=$'\t' read -r _grp _cmds; do
            [ -z "$_grp" ] && continue
            printf "  ${C_CYAN}%-10s${C_RESET} %s\n" "$_grp" "$_cmds"
        done < <(jq -r '.command_groups // {} | to_entries[] | "\(.key)\t\(.value | join("  "))"' "$ter_manifest" 2>/dev/null)
        unset _grp _cmds
    else
        # jq missing — degrade gracefully with a minimal hint.
        echo -e "  ${C_DIM}(install jq to render the command surface)${C_RESET}"
    fi

    # ── Registered apps — same manifest pattern, one source of truth ──
    if [ "$app_count" -gt 0 ] && command -v jq >/dev/null 2>&1; then
        echo -e "$RULE"
        echo -e "  ${C_BOLD}${C_CYAN}▰▰▰ REGISTERED APPS (${app_count})${C_RESET}"
        for _mf in "$HOME/.shell.d/apps"/*/manifest.json; do
            [ -f "$_mf" ] || continue
            local _name _ver _desc _cmds
            _name=$(jq -r '.name // "unknown"' "$_mf" 2>/dev/null)
            _ver=$(jq -r '.version // ""' "$_mf" 2>/dev/null)
            _desc=$(jq -r '.description // ""' "$_mf" 2>/dev/null)
            _cmds=$(jq -r '.commands // [] | join("  ")' "$_mf" 2>/dev/null)
            printf "  ${C_YELLOW}%s${C_RESET} ${C_DIM}v%s${C_RESET} — ${C_DIM}%s${C_RESET}\n" "$_name" "$_ver" "$_desc"
            [ -n "$_cmds" ] && printf "    ${C_GREEN}%s${C_RESET}\n" "$_cmds"
        done
        unset _mf _name _ver _desc _cmds
    fi
    echo -e "$RULE\n"
}
