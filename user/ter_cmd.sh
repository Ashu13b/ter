# ── TER OS Master Controller ──
# Interactive settings panel for startup features

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

    # Display Dashboard
    echo -e "\n\033[1;35m┌──────────────────────────────────────────────┐\033[0m"
    echo -e "\033[1;35m│\033[0m         ⚙️  \033[1mTER OS MASTER CONTROLLER\033[0m         \033[1;35m│\033[0m"
    echo -e "\033[1;35m├──────────────────────────────────────────────┤\033[0m"
    
    local t_state=$([ "$TMUX_AUTOSTART" = "true" ] && echo -e "\033[1;32mON \033[0m" || echo -e "\033[1;31mOFF\033[0m")
    local w_state=$([ "$WELCOME_DASHBOARD" = "true" ] && echo -e "\033[1;32mON \033[0m" || echo -e "\033[1;31mOFF\033[0m")
    local s_state=$([ "$OPTIMIZE_STATUS" = "true" ] && echo -e "\033[1;32mON \033[0m" || echo -e "\033[1;31mOFF\033[0m")
    
    echo -e "\033[1;35m│\033[0m  $t_state  [Tmux Tabs]      (ter toggle tmux)   \033[1;35m│\033[0m"
    echo -e "\033[1;35m│\033[0m  $w_state  [Welcome Matrix] (ter toggle welcome)\033[1;35m│\033[0m"
    echo -e "\033[1;35m│\033[0m  $s_state  [Status Audit]   (ter toggle status) \033[1;35m│\033[0m"
    echo -e "\033[1;35m└──────────────────────────────────────────────┘\033[0m\n"
}
