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
print(f'  {name:<14} v{ver:<6} [{cmds}]')
" 2>/dev/null
            done
            [ $found -eq 0 ] && echo "  No apps registered."
            unset _manifest
            ;;
        *)
            echo "Usage: apps [list]"
            ;;
    esac
}
