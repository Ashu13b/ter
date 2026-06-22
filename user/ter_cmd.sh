# ── TER OS Master Controller ──
# Interactive settings panel for startup features

_ter_apply_theme() {
    local active_fg="$1"
    local inactive_fg="$2"
    local accent="$3"
    local tab_fg="$4"
    local name="$5"

    local conf_file="$HOME/.tmux.conf"
    local repo_conf="$HOME/ter/.tmux.conf"

    # ~/.tmux.conf is a symlink to repo_conf (install.sh); editing the repo is
    # sufficient. Fall back to editing both if the symlink isn't set up yet.
    local targets="$repo_conf"
    [ ! -L "$conf_file" ] && [ -f "$conf_file" ] && targets="$conf_file $repo_conf"

    # Escape sed-replacement metachars (\, &, /) in the human-readable name.
    local name_esc
    name_esc=$(printf '%s' "$name" | sed -e 's/[\\&/]/\\&/g')

    for file in $targets; do
        [ -f "$file" ] || continue
        # Resolve symlinks so we rewrite the actual file, not a dangling link.
        local real; real=$(readlink -f "$file" 2>/dev/null || echo "$file")
        local tmp; tmp=$(mktemp "${real}.XXXXXX") || { echo "mktemp failed"; return 1; }
        sed -E \
            -e "s/status-left \"#\[range=user\|new_win,fg=colour[0-9]+,bold\]/status-left \"#\[range=user\|new_win,fg=colour$active_fg,bold\]/" \
            -e "s/status-right ' #\[fg=colour[0-9]+,bg=default,bold\]/status-right ' #\[fg=colour$active_fg,bg=default,bold\]/" \
            -e "s/status-format\[1\] \"#\[align=left\]     #\[list=on\]#\{W:             ,#\[bg=colour[0-9]+\]/status-format\[1\] \"#\[align=left\]     #\[list=on\]#\{W:             ,#\[bg=colour$accent\]/" \
            -e "s/window-status-current-style bg=colour[0-9]+,fg=colour[0-9]+/window-status-current-style bg=colour$accent,fg=colour$tab_fg/" \
            -e "s/# Soothing eye-preserving pane styles \((.*) - Transparent Backgrounds\)/# Soothing eye-preserving pane styles ($name_esc - Transparent Backgrounds)/" \
            -e "s/window-style 'bg=default,fg=colour[0-9]+'/window-style 'bg=default,fg=colour$inactive_fg'/" \
            -e "s/window-active-style 'bg=default,fg=colour[0-9]+'/window-active-style 'bg=default,fg=colour$active_fg'/" \
            "$real" > "$tmp" && mv "$tmp" "$real" || { rm -f "$tmp"; echo "theme write failed for $real"; return 1; }
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
        echo "  ter doctor    Check repo vs deployed drift"
        echo "  ter sync      Copy drifted runtime files back to repo"
        echo "  ter update    git pull + redeploy"
        echo "  ter snapshot  Diagnose pkg/storage state → device.lock"
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

    # Drift detector: compare repo source vs deployed runtime
    if [ "$1" = "doctor" ]; then
        local repo="$HOME/ter"
        local live="$HOME/.shell.d"
        local diffs=0
        echo -e "\n\033[1;36m  🩺 TER Doctor — repo vs deployed\033[0m"
        echo -e "\033[1;36m  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
        for dir in core network user docs; do
            [ -d "$repo/$dir" ] || continue
            while IFS= read -r f; do
                rel="${f#$repo/$dir/}"
                target="$live/$dir/$rel"
                if [ ! -e "$target" ]; then
                    echo -e "  \033[1;33m+ missing\033[0m  $dir/$rel"
                    diffs=$((diffs+1))
                elif ! cmp -s "$f" "$target"; then
                    echo -e "  \033[1;31m≠ drift  \033[0m  $dir/$rel"
                    diffs=$((diffs+1))
                fi
            done < <(find "$repo/$dir" -type f)
        done
        # Reverse: files in live but not in repo (excluding apps/)
        for dir in core network user docs; do
            [ -d "$live/$dir" ] || continue
            while IFS= read -r f; do
                rel="${f#$live/$dir/}"
                [ -e "$repo/$dir/$rel" ] || { echo -e "  \033[1;35m? orphan \033[0m  $dir/$rel"; diffs=$((diffs+1)); }
            done < <(find "$live/$dir" -type f)
        done
        if [ "$diffs" -eq 0 ]; then
            echo -e "  \033[1;32m✓ clean — repo and runtime match.\033[0m\n"
        else
            echo -e "\n  \033[1;33m$diffs difference(s) found.\033[0m Run 'bash ~/ter/install.sh' to redeploy.\n"
        fi
        return
    fi

    # Reverse drift: copy drifted runtime files back into the repo.
    if [ "$1" = "sync" ]; then
        local repo="$HOME/ter"
        local live="$HOME/.shell.d"
        local count=0
        echo -e "\n\033[1;36m  🔄 TER Sync — runtime → repo\033[0m"
        for dir in core network user docs; do
            [ -d "$repo/$dir" ] || continue
            while IFS= read -r f; do
                rel="${f#$live/$dir/}"
                src="$repo/$dir/$rel"
                if [ -e "$src" ] && ! cmp -s "$f" "$src"; then
                    cp "$f" "$src"
                    echo "  copied  $dir/$rel"
                    count=$((count+1))
                fi
            done < <(find "$live/$dir" -type f 2>/dev/null)
        done
        echo -e "  \033[1;32m✓ $count file(s) synced.\033[0m\n"
        return
    fi

    # Diagnostic snapshot of the current device.
    if [ "$1" = "snapshot" ]; then
        local out="$HOME/ter/device.lock"
        echo -e "\n\033[1;36m  📸 TER Snapshot → device.lock\033[0m"
        {
            echo "# device.lock — generated by 'ter snapshot' on $(date -Iseconds)"
            echo "# Diagnostic only. Source of truth for required pkgs is packages.txt."
            echo ""
            echo "## uname"
            uname -a 2>/dev/null
            echo ""
            echo "## termux-info"
            command -v termux-info >/dev/null 2>&1 && termux-info 2>/dev/null || echo "(termux-info not installed)"
            echo ""
            echo "## storage permission"
            [ -d "$HOME/storage" ] && echo "granted" || echo "MISSING (run termux-setup-storage)"
            echo ""
            echo "## installed packages"
            command -v pkg >/dev/null 2>&1 && pkg list-installed 2>/dev/null | sed -n 's|/.*||p' | sort -u
            echo ""
            echo "## ter required (packages.txt)"
            [ -f "$HOME/ter/packages.txt" ] && grep -vE '^\s*(#|$)' "$HOME/ter/packages.txt" | sort -u
            echo ""
            echo "## ter required NOT installed"
            if [ -f "$HOME/ter/packages.txt" ] && command -v pkg >/dev/null 2>&1; then
                want=$(grep -vE '^\s*(#|$)' "$HOME/ter/packages.txt" | sort -u)
                have=$(pkg list-installed 2>/dev/null | sed -n 's|/.*||p' | sort -u)
                comm -23 <(echo "$want") <(echo "$have")
            fi
        } > "$out"
        echo "  written: $out"
        local missing; missing=$(awk '/^## ter required NOT installed$/{flag=1; next} /^$/{flag=0} flag' "$out" | grep -v '^$' | wc -l)
        if [ "$missing" -gt 0 ]; then
            echo -e "  \033[1;33m⚠ $missing required pkg(s) missing — run install.sh.\033[0m\n"
        else
            echo -e "  \033[1;32m✓ all required packages present.\033[0m\n"
        fi
        return
    fi

    # Pull from GitHub and redeploy.
    if [ "$1" = "update" ]; then
        local repo="$HOME/ter"
        echo -e "\n\033[1;36m  ⬇  TER Update\033[0m"
        ( cd "$repo" && git pull --ff-only ) || { echo "git pull failed"; return 1; }
        ( cd "$repo" && bash install.sh ) || return 1
        echo -e "  \033[1;32m✓ Updated. Run 're' or open a new terminal.\033[0m\n"
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
                    _ter_apply_theme 179 137 239 179 "Obsidian Black & Amber Gold"
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
                _ter_apply_theme 179 137 239 179 "Obsidian Black & Amber Gold"
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
