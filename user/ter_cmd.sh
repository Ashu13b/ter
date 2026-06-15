# ── TER OS Master Controller ──
# Interactive settings panel for startup features

_ter_apply_theme() {
    local active_fg="$1"
    local inactive_fg="$2"
    local accent="$3"
    local tab_fg="$4"
    local name="$5"

    local conf_file="$HOME/.tmux.conf"
    local repo_conf="/data/data/com.termux/files/home/ter/.tmux.conf"

    for file in "$conf_file" "$repo_conf"; do
        [ -f "$file" ] || continue
        sed -i -E "s/status-left \"#\[range=user\|new_win,fg=colour[0-9]+,bold\]/status-left \"#\[range=user\|new_win,fg=colour$active_fg,bold\]/" "$file"
        sed -i -E "s/status-right ' #\[fg=colour[0-9]+,bg=default,bold\]/status-right ' #\[fg=colour$active_fg,bg=default,bold\]/" "$file"
        sed -i -E "s/status-format\[1\] \"#\[align=left\]     #\[list=on\]#\{W:             ,#\[bg=colour[0-9]+\]/status-format\[1\] \"#\[align=left\]     #\[list=on\]#\{W:             ,#\[bg=colour$accent\]/" "$file"
        sed -i -E "s/window-status-current-style bg=colour[0-9]+,fg=colour[0-9]+/window-status-current-style bg=colour$accent,fg=colour$tab_fg/" "$file"
        sed -i -E "s/# Soothing eye-preserving pane styles \((.*) - Transparent Backgrounds\)/# Soothing eye-preserving pane styles ($name - Transparent Backgrounds)/" "$file"
        sed -i -E "s/window-style 'bg=default,fg=colour[0-9]+'/window-style 'bg=default,fg=colour$inactive_fg'/" "$file"
        sed -i -E "s/window-active-style 'bg=default,fg=colour[0-9]+'/window-active-style 'bg=default,fg=colour$active_fg'/" "$file"
    done

    tmux source-file "$conf_file" 2>/dev/null || true
}

ter() {
    local conf="$HOME/.config/ter/startup.conf"
    mkdir -p "$HOME/.config/ter"
    
    # Initialize defaults if missing
    if [ ! -f "$conf" ]; then
        cat > "$conf" << 'EOF'
TMUX_AUTOSTART=true
WELCOME_DASHBOARD=true
OPTIMIZE_STATUS=true
EOF
    fi

    # Read current state
    source "$conf"

    # Help screen
    if [ "$1" = "-h" ] || [ "$1" = "--help" ] || [ "$1" = "help" ]; then
        echo ""
        echo -e "\033[1;36m  ⌨️  TER OS — Quick Reference\033[0m"
        echo -e "\033[1;36m  ━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
        echo ""
        echo -e "\033[1;33m  TMUX SHORTCUTS (Prefix: ~)\033[0m"
        echo "  ~ c      New tab"
        echo "  ~ n / p  Next / Prev tab"
        echo "  ~ |      Split vertical"
        echo "  ~ -      Split horizontal"
        echo "  ~ ←↑↓→   Jump splits"
        echo "  ~ x      Close split/tab"
        echo "  ~ m      Mouse ON/OFF"
        echo "  Tap ⏭    Cycle tabs"
        echo ""
        echo -e "\033[1;33m  KEYBOARD (Swipe Up)\033[0m"
        echo "  ~ ↑      |  (pipe)"
        echo "  ESC ↑    exit"
        echo "  / ↑      Ctrl+C"
        echo "  ssh ↑    portal"
        echo "  p ↑      clear"
        echo ""
        echo -e "\033[1;33m  TER COMMANDS\033[0m"
        echo "  ter           Settings panel"
        echo "  ter toggle    tmux|welcome|status"
        echo "  ter theme     Switch eye-preserving themes"
        echo "  re            Reload shell"
        echo "  tabname       Rename tab"
        echo "  optimize      BG stability"
        echo "  adbcon        ADB connect"
        echo "  scan          Network scan"
        echo "  apps          App registry"
        echo ""
        echo -e "\033[1;36m  📖 Full manual: cat ~/.shell.d/docs/cli_manual.md\033[0m"
        echo ""
        return
    fi

    # Handle toggles
    if [ "$1" = "toggle" ]; then
        case "$2" in
            tmux)
                if [ "$TMUX_AUTOSTART" = "true" ]; then sed -i 's/TMUX_AUTOSTART=true/TMUX_AUTOSTART=false/' "$conf"; else sed -i 's/TMUX_AUTOSTART=false/TMUX_AUTOSTART=true/' "$conf"; fi
                ;;
            welcome)
                if [ "$WELCOME_DASHBOARD" = "true" ]; then 
                    sed -i 's/WELCOME_DASHBOARD=true/WELCOME_DASHBOARD=false/' "$conf"
                    touch "$HOME/.hushlogin"
                else 
                    sed -i 's/WELCOME_DASHBOARD=false/WELCOME_DASHBOARD=true/' "$conf"
                    rm -f "$HOME/.hushlogin"
                fi
                ;;
            status)
                if [ "$OPTIMIZE_STATUS" = "true" ]; then sed -i 's/OPTIMIZE_STATUS=true/OPTIMIZE_STATUS=false/' "$conf"; else sed -i 's/OPTIMIZE_STATUS=false/OPTIMIZE_STATUS=true/' "$conf"; fi
                ;;
            *)
                echo "Usage: ter toggle [tmux|welcome|status]"
                return
                ;;
        esac
        echo -e "\033[1;32m✓ Toggled $2.\033[0m Run 're' to reload terminal."
        return
    fi

    # Handle theme selection
    if [ "$1" = "theme" ]; then
        if [ -n "$2" ]; then
            case "$2" in
                C|c|solarized)
                    _ter_apply_theme 108 253 136 232 "Solarized & Sage Green"
                    ;;
                F|f|midnight)
                    _ter_apply_theme 189 253 211 232 "Midnight Indigo & Soft Lavender"
                    ;;
                G|g|charcoal)
                    _ter_apply_theme 223 187 215 232 "Charcoal Coffee & Warm Sand"
                    ;;
                H|h|aubergine)
                    _ter_apply_theme 224 181 173 232 "Aubergine Wine & Peach Cream"
                    ;;
                I|i|obsidian)
                    _ter_apply_theme 179 137 237 179 "Obsidian Black & Amber Gold"
                    ;;
                *)
                    echo "Unknown theme: $2"
                    echo "Available themes: c (solarized), f (midnight), g (charcoal), h (aubergine), i (obsidian)"
                    return 1
                    ;;
            esac
            echo -e "\033[1;32m✓ Theme updated to $2.\033[0m"
            return
        fi

        # Interactive Menu
        echo -e "\n\033[1;36m  🎨 TER OS Theme Switcher\033[0m"
        echo -e "\033[1;36m  ━━━━━━━━━━━━━━━━━━━━━━\033[0m"
        echo "  [C] Solarized & Sage Green"
        echo "  [F] Midnight Indigo & Soft Lavender"
        echo "  [G] Charcoal Coffee & Warm Sand"
        echo "  [H] Aubergine Wine & Peach Cream"
        echo "  [I] Obsidian Black & Amber Gold"
        echo ""
        read -p "Select theme [C/F/G/H/I]: " choice
        case "$choice" in
            [Cc])
                _ter_apply_theme 108 253 136 232 "Solarized & Sage Green"
                ;;
            [Ff])
                _ter_apply_theme 189 253 211 232 "Midnight Indigo & Soft Lavender"
                ;;
            [Gg])
                _ter_apply_theme 223 187 215 232 "Charcoal Coffee & Warm Sand"
                ;;
            [Hh])
                _ter_apply_theme 224 181 173 232 "Aubergine Wine & Peach Cream"
                ;;
            [Ii])
                _ter_apply_theme 179 137 237 179 "Obsidian Black & Amber Gold"
                ;;
            *)
                echo "No changes made."
                return
                ;;
        esac
        echo -e "\033[1;32m✓ Theme updated successfully!\033[0m"
        return
    fi

    # Display Dashboard
    echo -e "\n\033[1;35m┌──────────────────────────────────────────────┐\033[0m"
    echo -e "\033[1;35m│\033[0m         ⚙️  \033[1mTER OS MASTER CONTROLLER\033[0m         \033[1;35m│\033[0m"
    echo -e "\033[1;35m├──────────────────────────────────────────────┤\033[0m"
    
    local t_state=$([ "$TMUX_AUTOSTART" = "true" ] && echo -e "\033[1;32mON \033[0m" || echo -e "\033[1;31mOFF\033[0m")
    local w_state=$([ "$WELCOME_DASHBOARD" = "true" ] && echo -e "\033[1;32mON \033[0m" || echo -e "\033[1;31mOFF\033[0m")
    local s_state=$([ "$OPTIMIZE_STATUS" = "true" ] && echo -e "\033[1;32mON \033[0m" || echo -e "\033[1;31mOFF\033[0m")
    
    local raw_theme=$(sed -n -E 's/.*Soothing eye-preserving pane styles \((.*) - Transparent Backgrounds\).*/\1/p' "$HOME/.tmux.conf" 2>/dev/null || echo "Default")
    local theme_disp="${raw_theme:0:21}"
    local padded_theme=$(printf "%-30s" "  Theme: $theme_disp")
    
    echo -e "\033[1;35m│\033[0m  $t_state  [Tmux Tabs]      (ter toggle tmux)   \033[1;35m│\033[0m"
    echo -e "\033[1;35m│\033[0m  $w_state  [Welcome Matrix] (ter toggle welcome)\033[1;35m│\033[0m"
    echo -e "\033[1;35m│\033[0m  $s_state  [Status Audit]   (ter toggle status) \033[1;35m│\033[0m"
    echo -e "\033[1;35m│\033[0m$padded_theme(ter theme)     \033[1;35m│\033[0m"
    echo -e "\033[1;35m└──────────────────────────────────────────────┘\033[0m\n"
}
