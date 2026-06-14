# ── App Registration Loader ──
# Scans ~/.shell.d/apps/*/ and sources all .sh files from registered apps

if [ -d "$HOME/.shell.d/apps" ]; then
    for _app_dir in "$HOME/.shell.d/apps"/*/; do
        [ -d "$_app_dir" ] || continue
        for _app_f in $(find "$_app_dir" -maxdepth 1 -name "*.sh" | sort); do
            source "$_app_f"
        done
    done
    unset _app_dir _app_f
fi

# ── App Registry Command ──
apps() {
    if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]] || [[ "$1" == "help" ]]; then
        echo -e "${C_BOLD}${C_CYAN}─── TERMUX APP REGISTRY HELP ───${C_RESET}"
        echo "Usage: apps [list]"
        echo ""
        echo "Description:"
        echo "  Manages and lists registered shell integration applications."
        echo "  Apps are loaded dynamically from ~/.shell.d/apps/<app_name>/"
        echo "  containing manifest.json, aliases, autocomplete, and welcome hooks."
        echo ""
        return 0
    fi

    case "$1" in
        list|"")
            echo -e "${C_CYAN}Registered Apps:${C_RESET}"
            local found=0
            for _manifest in "$HOME/.shell.d/apps"/*/manifest.json; do
                [ -f "$_manifest" ] || continue
                found=1
                local info; info=$(python3 -c "
import sys, json
m = json.load(open(sys.argv[1]))
print(f\"{m.get('name', 'unknown')}|{m.get('version', '?')}|{', '.join(m.get('commands', []))}\")
" "$_manifest" 2>/dev/null)
                IFS='|' read -r name ver cmds <<< "$info"
                local padded_name; padded_name=$(printf "%-14s" "$name")
                local link; link=$(style_link "file://$_manifest" "$padded_name")
                echo -e "  ${link} v${ver} [${cmds}]"
            done
            [ $found -eq 0 ] && echo "  No apps registered."
            unset _manifest
            ;;
        *)
            echo -e "${C_RED}❌ Unknown option: $1${C_RESET}"
            echo "Usage: apps [list]"
            return 1
            ;;
    esac
}
