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
                python3 -c "
import json
m = json.load(open('$_manifest'))
name = m.get('name', 'unknown')
ver = m.get('version', '?')
cmds = ', '.join(m.get('commands', []))
padded_name = f'{name:<14}'
link = f'\033]8;;file://$_manifest\033\\{padded_name}\033]8;;\033\\'
print(f'  {link} v{ver:<6} [{cmds}]')
" 2>/dev/null
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
