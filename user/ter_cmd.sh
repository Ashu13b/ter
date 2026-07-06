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
        echo "  ter wizard    First-run setup (git, ssh, gh, secrets)"
        echo "  ter toggle    tmux|welcome|status"
        echo "  ter theme     Switch eye-preserving themes"
        echo "  ter doctor    Check repo vs deployed drift"
        echo "  ter sync      Copy drifted runtime files back to repo"
        echo "  ter update    git pull + redeploy"
        echo "  ter snapshot  Diagnose pkg/storage state → device.lock"
        echo "  ter info      One-screen status (version, drift, pkgs)"
        echo "  ter shortcut  Pin shortcuts to Android home screen"
        echo "  re            Reload shell"
        echo "  tabname       Rename tab"
        echo "  optimize      BG stability"
        echo "  adbcon        ADB connect"
        echo "  adb-apk       Smart APK Installer"
        echo "  dvop          Developer Options Toggle"
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
        local quiet=0
        [ "$2" = "--quiet" ] || [ "$2" = "-q" ] && quiet=1
        if [ "$quiet" -eq 0 ]; then
            echo -e "\n\033[1;36m  🩺 TER Doctor — repo vs deployed\033[0m"
            echo -e "\033[1;36m  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
        fi
        for dir in core network user docs; do
            [ -d "$repo/$dir" ] || continue
            while IFS= read -r f; do
                rel="${f#$repo/$dir/}"
                target="$live/$dir/$rel"
                if [ ! -e "$target" ]; then
                    [ "$quiet" -eq 0 ] && echo -e "  \033[1;33m+ missing\033[0m  $dir/$rel"
                    diffs=$((diffs+1))
                elif ! cmp -s "$f" "$target"; then
                    [ "$quiet" -eq 0 ] && echo -e "  \033[1;31m≠ drift  \033[0m  $dir/$rel"
                    diffs=$((diffs+1))
                fi
            done < <(find "$repo/$dir" -type f)
        done
        # Reverse: files in live but not in repo (excluding apps/)
        for dir in core network user docs; do
            [ -d "$live/$dir" ] || continue
            while IFS= read -r f; do
                rel="${f#$live/$dir/}"
                if [ ! -e "$repo/$dir/$rel" ]; then
                    [ "$quiet" -eq 0 ] && echo -e "  \033[1;35m? orphan \033[0m  $dir/$rel"
                    diffs=$((diffs+1))
                fi
            done < <(find "$live/$dir" -type f)
        done
        if [ "$quiet" -eq 0 ]; then
            if [ "$diffs" -eq 0 ]; then
                echo -e "  \033[1;32m✓ clean — repo and runtime match.\033[0m"
            else
                echo -e "\n  \033[1;33m$diffs difference(s) found.\033[0m Run 'bash ~/ter/install.sh' to redeploy."
            fi
        elif [ "$diffs" -gt 0 ]; then
            echo -e "\033[1;33m⚠ ter doctor:\033[0m $diffs repo↔runtime drift(s) — run \`ter doctor\` for detail."
        fi
        # Secrets check: warn on vars listed in template but unset in environment.
        if [ -f "$HOME/ter/secrets.template" ]; then
            local unset_n=0 missing_vars=""
            while IFS= read -r line; do
                local var="${line%%=*}"
                [ -z "$var" ] && continue
                if [ -z "$(printenv "$var" 2>/dev/null)" ]; then
                    unset_n=$((unset_n+1))
                    missing_vars="$missing_vars $var"
                fi
            done < <(grep -E '^[A-Z_][A-Z0-9_]*=' "$HOME/ter/secrets.template")
            if [ "$unset_n" -gt 0 ]; then
                if [ "$quiet" -eq 0 ]; then
                    echo -e "\n  \033[1;33m⚠ $unset_n secret(s) unset:\033[0m$missing_vars"
                    echo -e "    Edit ~/.config/ter/secrets.env (copy from secrets.template)."
                fi
                # secrets absence is intentional-ish — don't nag in quiet mode.
            fi
        fi
        # Services health: sshd listener on the Termux default port.
        # NEXUS and any inbound reverse-tunnel path assume :8022 is answering.
        # A silent sshd is the exact failure mode that flapped NEXUS for hours.
        if [ -f "$PREFIX/etc/ssh/sshd_config" ]; then
            local sshd_port sshd_status
            sshd_port=$(awk '/^Port /{print $2; exit}' "$PREFIX/etc/ssh/sshd_config")
            sshd_port="${sshd_port:-8022}"
            sshd_status=$(sv status sshd 2>/dev/null | awk '{print $1}')
            if ! nc -z 127.0.0.1 "$sshd_port" 2>/dev/null; then
                if [ "$quiet" -eq 1 ]; then
                    echo -e "\033[1;33m⚠ ter doctor:\033[0m sshd not listening on :$sshd_port — run \`sv up sshd\`."
                else
                    echo -e "\n  \033[1;33m⚠ sshd not listening on :$sshd_port\033[0m (sv: ${sshd_status:-unknown})"
                    echo -e "    Fix: \033[1;37msv up sshd\033[0m  (or \033[1;37msv restart sshd\033[0m)"
                    [ "$sshd_port" != "8022" ] && echo -e "    Note: NEXUS + adbcon expect :8022 — current config is :$sshd_port."
                fi
            elif [ "$sshd_port" != "8022" ]; then
                if [ "$quiet" -eq 1 ]; then
                    echo -e "\033[1;33m⚠ ter doctor:\033[0m sshd on :$sshd_port (NEXUS expects :8022)."
                else
                    echo -e "\n  \033[1;33m⚠ sshd on non-default port :$sshd_port\033[0m — NEXUS assumes :8022."
                fi
            fi
        fi
        [ "$quiet" -eq 0 ] && echo ""
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

    # One-screen "where am I" status.
    if [ "$1" = "info" ]; then
        local repo="$HOME/ter"
        local sha tag dirty drift theme banner
        sha=$(git -C "$repo" rev-parse --short HEAD 2>/dev/null || echo "?")
        tag=$(git -C "$repo" describe --tags --always 2>/dev/null || echo "$sha")
        git -C "$repo" diff --quiet 2>/dev/null && dirty="clean" || dirty="dirty"
        # Drift = number of files differing between repo and runtime.
        drift=0
        for d in core network user docs; do
            [ -d "$repo/$d" ] && [ -d "$HOME/.shell.d/$d" ] || continue
            while IFS= read -r f; do
                rel="${f#$repo/$d/}"
                t="$HOME/.shell.d/$d/$rel"
                [ -e "$t" ] && cmp -s "$f" "$t" || drift=$((drift+1))
            done < <(find "$repo/$d" -type f 2>/dev/null)
        done
        theme=$(sed -n -E 's/.*Soothing eye-preserving pane styles \((.*) - Transparent Backgrounds\).*/\1/p' "$HOME/.tmux.conf" 2>/dev/null)
        banner=$([ "${OPTIMIZE_STATUS:-true}" = "true" ] && echo "on" || echo "off")
        local pkgs_missing="?"
        if [ -f "$repo/packages.txt" ] && command -v pkg >/dev/null 2>&1; then
            want=$(grep -vE '^\s*(#|$)' "$repo/packages.txt" | sort -u)
            have=$(pkg list-installed 2>/dev/null | sed -n 's|/.*||p' | sort -u)
            pkgs_missing=$(comm -23 <(echo "$want") <(echo "$have") | grep -vc '^$')
        fi
        echo -e "\n\033[1;36m  ℹ  TER Info\033[0m"
        echo -e "  \033[1;33mversion\033[0m   ${TER_VERSION:-?}  (${tag}, ${dirty})"
        echo -e "  \033[1;33mrepo\033[0m      $repo"
        echo -e "  \033[1;33mtheme\033[0m     ${theme:-default}"
        echo -e "  \033[1;33mdrift\033[0m     $drift file(s) differ from runtime"
        echo -e "  \033[1;33mpackages\033[0m  $pkgs_missing missing (vs packages.txt)"
        echo -e "  \033[1;33mbanner\033[0m    $banner"
        echo -e "  \033[1;33mshell\033[0m     ${CURRENT_SHELL:-?}  pid=$$"
        echo -e "  \033[1;33mtmux\033[0m      ${TMUX:+attached}${TMUX:-detached}"
        # ADB + dvop visibility so lockout risk is obvious before running `dvop off`.
        if command -v adb >/dev/null 2>&1; then
            local adb_state="disconnected" dvop_state="?"
            if adb devices 2>/dev/null | grep -q "device$"; then
                adb_state="connected"
                dvop_state=$(adb shell settings get global development_settings_enabled 2>/dev/null | tr -d '\r')
                [ "$dvop_state" = "1" ] && dvop_state="ON" || dvop_state="OFF"
            fi
            echo -e "  \033[1;33madb\033[0m       $adb_state  (dvop=$dvop_state)"
        fi
        echo ""
        return
    fi

    # First-run interactive setup. Idempotent — re-run any time.
    if [ "$1" = "wizard" ]; then
        echo -e "\n\033[1;36m  🧙 TER Wizard — first-run setup\033[0m"
        echo -e "\033[1;36m  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"

        # Storage permission.
        if [ ! -d "$HOME/storage" ]; then
            echo "→ requesting Android storage permission"
            command -v termux-setup-storage >/dev/null && termux-setup-storage
        else
            echo "✓ storage permission granted"
        fi

        # Git identity.
        local g_name g_email
        g_name=$(git config --global user.name 2>/dev/null)
        g_email=$(git config --global user.email 2>/dev/null)
        if [ -z "$g_name" ]; then
            read -p "git user.name: " g_name
            [ -n "$g_name" ] && git config --global user.name "$g_name"
        else
            echo "✓ git user.name=$g_name"
        fi
        if [ -z "$g_email" ]; then
            read -p "git user.email: " g_email
            [ -n "$g_email" ] && git config --global user.email "$g_email"
        else
            echo "✓ git user.email=$g_email"
        fi

        # SSH key.
        if [ ! -f "$HOME/.ssh/id_ed25519" ]; then
            read -p "Generate ed25519 SSH key? [Y/n] " yn
            case "$yn" in
                ""|[Yy]*) ssh-keygen -t ed25519 -C "${g_email:-termux}" -f "$HOME/.ssh/id_ed25519" -N "";;
            esac
        else
            echo "✓ ssh key present: ~/.ssh/id_ed25519"
        fi

        # GitHub auth.
        if command -v gh >/dev/null 2>&1; then
            if ! gh auth status >/dev/null 2>&1; then
                read -p "Run 'gh auth login' now? [Y/n] " yn
                case "$yn" in ""|[Yy]*) gh auth login;; esac
            else
                echo "✓ gh authenticated"
            fi
        fi

        # Secrets scaffold.
        local sec_dir="$HOME/.config/ter"
        local sec_file="$sec_dir/secrets.env"
        if [ ! -f "$sec_file" ] && [ -f "$HOME/ter/secrets.template" ]; then
            mkdir -p "$sec_dir"
            cp "$HOME/ter/secrets.template" "$sec_file"
            chmod 600 "$sec_file"
            echo "→ created $sec_file — edit to fill in values"
        else
            echo "✓ secrets file: $sec_file"
        fi

        echo -e "\n  \033[1;32m✓ Wizard done.\033[0m Open a new shell or run 're'.\n"
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

    # Create Home Screen Shortcuts (via Termux:Widget + ADB Pinning Activity)
    if [ "$1" = "shortcut" ]; then
        if [ -n "$2" ]; then
            local name="$2"
            local cmd=""
            shift 2
            cmd="$*"
            if [ -z "$cmd" ]; then
                echo "Usage: ter shortcut <name> <command>"
                echo "Example: ter shortcut adb-wizard adbcon"
                return 1
            fi

            # 1. Ensure directory exists
            mkdir -p "$HOME/.shortcuts"

            # 2. Write the script
            cat > "$HOME/.shortcuts/$name" << EOF
#!/data/data/com.termux/files/usr/bin/bash
# Generated by 'ter shortcut' on $(date -Iseconds)
echo -e "🚀 \e[1;36mRunning: $name\e[0m"
echo -e "  \e[37mCommand: $cmd\e[0m\n"
$cmd
echo -e "\n\e[1;32m✔ Execution finished.\e[0m"
echo -ne "Press Enter to exit..."
read -r
EOF
            chmod +x "$HOME/.shortcuts/$name"
            echo -e "✅ \e[1;32mCreated shortcut script:\e[0m ~/.shortcuts/$name"

            # 3. Trigger ADB pinning activity if ADB is available
            # Note: We source adb_utils.sh to get _get_adb_device helper if needed
            local dev=""
            if command -v adb &>/dev/null; then
                # Sourcing is done inside subshell to avoid polluting namespace
                dev=$(source "$HOME/.shell.d/user/adb_utils.sh" 2>/dev/null && _get_adb_device 2>/dev/null)
            fi

            if [ -n "$dev" ]; then
                echo "📱 Requesting launcher to pin shortcut via ADB..."
                # Start TermuxCreateShortcutActivity to request pinning on screen
                adb -s "$dev" shell am start -n com.termux.widget/com.termux.widget.TermuxCreateShortcutActivity >/dev/null 2>&1
                if [ $? -eq 0 ]; then
                    echo -e "🎉 \e[1;32mShortcut creation activity launched on phone screen!\e[0m"
                    echo "   Select '$name' in the popup to place it on your home screen."
                else
                    echo -e "⚠️  Could not launch Termux:Widget activity automatically."
                    echo "   Make sure 'Termux:Widget' app is installed on your phone."
                fi
            else
                echo -e "💡 Run \`adbcon\` first to automatically trigger the Android home screen pinning dialog."
                echo "   Otherwise, add the 'Termux Widget' to your home screen manually."
            fi
            return 0
        fi

        # Help / interactive mode
        echo -e "\n\033[1;36m  📱 TER OS Home Screen Shortcut Creator\033[0m"
        echo -e "\033[1;36m  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
        echo "Usage: ter shortcut <name> <command>"
        echo ""
        echo "Examples:"
        echo "  ter shortcut adb-wizard adbcon"
        echo "  ter shortcut sys-info adb-sysinfo"
        echo "  ter shortcut nexus-watch 'python3 ~/nexus/nexus.py watch'"
        echo ""
        echo "Note: Requires the 'Termux:Widget' app installed on your phone."
        return 0
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
                    _ter_apply_theme 179 137 179 232 "Obsidian Black & Amber Gold"
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
                _ter_apply_theme 179 137 179 232 "Obsidian Black & Amber Gold"
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
