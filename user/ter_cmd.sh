# ── TER OS Master Controller ──
# Interactive settings panel for startup features

# Older loaders may not export this yet; discover the installed source checkout.
if [ -z "${TER_REPO_DIR:-}" ] && [ -r "$HOME/.shell.d/.ter-repo" ]; then
    IFS= read -r TER_REPO_DIR < "$HOME/.shell.d/.ter-repo"
    export TER_REPO_DIR
fi

_ter_safe_shortcut_name() {
    case "$1" in
        ""|*/*|*..*|*[!A-Za-z0-9._-]*) return 1 ;;
    esac
}

_ter_apply_theme() {
    local active_fg="$1"
    local inactive_fg="$2"
    local accent="$3"
    local tab_fg="$4"
    local name="$5"

    local conf_file="$HOME/.tmux.conf"
    local repo_conf="${TER_REPO_DIR:-$HOME/ter}/.tmux.conf"

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

# ── Theme registry ──
# Single source of truth for palettes: key -> "inactive|active|accent|Name".
_ter_theme_spec() {
    case "$1" in
        C|c|solarized)  printf '%s\n' "108|253|136|Solarized & Sage Green" ;;
        F|f|midnight)   printf '%s\n' "189|253|211|Midnight Indigo & Soft Lavender" ;;
        G|g|charcoal)   printf '%s\n' "223|187|215|Charcoal Coffee & Warm Sand" ;;
        H|h|aubergine)  printf '%s\n' "224|181|173|Aubergine Wine & Peach Cream" ;;
        I|i|obsidian)   printf '%s\n' "179|137|179|Obsidian Black & Amber Gold" ;;
        J|j|nord)       printf '%s\n' "110|139|75|Nord Frost & Glacier Blue" ;;
        K|k|ocean)      printf '%s\n' "66|109|80|Ocean Deep & Aqua Glow" ;;
        L|l|rose)       printf '%s\n' "181|218|168|Rose Quartz & Blush Pink" ;;
        M|m|matrix)     printf '%s\n' "65|114|46|Matrix Emerald & Neon Lime" ;;
        N|n|sunset)     printf '%s\n' "131|209|202|Sunset Ember & Coral Bloom" ;;
    esac
}

_ter_theme_keys() {
    printf '%s\n' C F G H I J K L M N
}

_ter_set_theme() {
    local spec inactive active rest accent name
    spec=$(_ter_theme_spec "$1")
    if [ -z "$spec" ]; then
        echo "Unknown theme: $1"
        echo "Available themes: c f g h i j k l m n (or 'ter theme next')"
        return 1
    fi
    inactive="${spec%%|*}"
    rest="${spec#*|}"
    active="${rest%%|*}"
    rest="${rest#*|}"
    accent="${rest%%|*}"
    name="${rest#*|}"
    _ter_apply_theme "$inactive" "$active" "$accent" 232 "$name"
    echo -e "\033[1;32m✓ Theme updated to $name.\033[0m"
}

# Rotate to the palette after the currently applied one (wraps around).
_ter_theme_next() {
    local cur key spec name prev_key="" first_key=""
    cur=$(sed -n -E 's/.*Soothing eye-preserving pane styles \((.*) - Transparent Backgrounds\).*/\1/p' "$HOME/.tmux.conf" 2>/dev/null)
    while IFS= read -r key; do
        [ -n "$first_key" ] || first_key="$key"
        spec=$(_ter_theme_spec "$key") || continue
        name="${spec##*|}"
        if [ "$name" = "$cur" ]; then
            prev_key="$key"
            continue
        fi
        if [ -n "$prev_key" ]; then
            _ter_set_theme "$key"
            return
        fi
    done < <(_ter_theme_keys)
    # Unknown current theme or wrapped past the last palette -> go to first.
    _ter_set_theme "$first_key"
}

_ter_is_ignored() {
    local rel_path="$1"
    local file_name="${rel_path##*/}"
    
    # Built-in ignore defaults
    case "$file_name" in
        *.pyc|*.tmp|*.bak|tmp_*|test_*|scratch_*) return 0 ;;
    esac
    case "$rel_path" in
        */__pycache__/*|__pycache__/*|local/*|*/local/*) return 0 ;;
    esac

    # Check .terignore
    local ignore_file="$HOME/.shell.d/.terignore"
    [ -f "$ignore_file" ] || ignore_file="${TER_REPO_DIR:-$HOME/ter}/.terignore"
    if [ -f "$ignore_file" ]; then
        local pat
        while IFS= read -r pat || [ -n "$pat" ]; do
            pat=$(echo "$pat" | sed -e 's/[[:space:]]*#.*$//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
            [ -n "$pat" ] || continue
            case "$rel_path" in
                $pat) return 0 ;;
            esac
            case "$file_name" in
                $pat) return 0 ;;
            esac
        done < "$ignore_file"
    fi
    return 1
}

ter() {
    local conf="$HOME/.config/ter/startup.conf"
    mkdir -p "$HOME/.config/ter"
    
    # Initialize defaults if missing, then parse only the supported values.
    # Do not source this user-editable data file as shell code.
    if [ ! -f "$conf" ]; then
        cat > "$conf" << 'EOF'
TMUX_AUTOSTART=true
WELCOME_DASHBOARD=true
OPTIMIZE_STATUS=false
EOF
    fi
    if type _ter_load_startup_config >/dev/null 2>&1; then
        _ter_load_startup_config
    else
        TMUX_AUTOSTART=true
        WELCOME_DASHBOARD=true
        OPTIMIZE_STATUS=false
    fi

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
        echo "  ter theme     Switch eye-preserving themes ('ter theme next' rotates)"
        echo "  ter doctor    Check repo vs deployed drift"
        echo "  ter sync      Copy drifted runtime files back to repo"
        echo "  ter update    git pull + redeploy"
        echo "  ter snapshot  Diagnose pkg/storage state → device.lock"
        echo "  ter info      One-screen status (version, drift, pkgs)"
        echo "  ter shortcut  Pin shortcuts to home screen (add | list | rm)"
        echo "  ter perms     Grant Android/ColorOS permissions for foreground shortcuts"
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

    # Diagnostics check for doctor
    if [ "$1" = "doctor" ]; then
        local repo="${TER_REPO_DIR:-$HOME/ter}"
        local live="$HOME/.shell.d"
        local diffs=0 quiet=0
        [ "${2:-}" = "-q" ] || [ "${2:-}" = "--quiet" ] && quiet=1
        [ "$quiet" -eq 0 ] && echo -e "\n\033[1;36m  🩺 TER Doctor — repo vs runtime check\033[0m"
        for dir in core network user docs; do
            [ -d "$repo/$dir" ] || continue
            while IFS= read -r f; do
                rel="${f#$repo/$dir/}"
                target="$live/$dir/$rel"
                _ter_is_ignored "$dir/$rel" && continue
                if [ ! -e "$target" ]; then
                    [ "$quiet" -eq 0 ] && echo -e "  \033[1;33m+ missing\033[0m  $dir/$rel"
                    diffs=$((diffs+1))
                elif ! cmp -s "$f" "$target"; then
                    [ "$quiet" -eq 0 ] && echo -e "  \033[1;31m≠ drift  \033[0m  $dir/$rel"
                    diffs=$((diffs+1))
                fi
            done < <(find "$repo/$dir" -type f 2>/dev/null)
        done
        # Reverse: files in live but not in repo (excluding apps/ and ignored files)
        for dir in core network user docs; do
            [ -d "$live/$dir" ] || continue
            while IFS= read -r f; do
                rel="${f#$live/$dir/}"
                _ter_is_ignored "$dir/$rel" && continue
                if [ ! -e "$repo/$dir/$rel" ]; then
                    [ "$quiet" -eq 0 ] && echo -e "  \033[1;35m? new/untracked \033[0m  $dir/$rel"
                    diffs=$((diffs+1))
                fi
            done < <(find "$live/$dir" -type f 2>/dev/null)
        done
        if [ "$quiet" -eq 0 ]; then
            if [ "$diffs" -eq 0 ]; then
                echo -e "  \033[1;32m✓ clean — repo and runtime match.\033[0m"
            else
                echo -e "\n  \033[1;33m$diffs difference(s) found.\033[0m Run 'ter sync' to review and import into repo, or 'bash ~/ter/install.sh' to redeploy."
            fi
        elif [ "$diffs" -gt 0 ]; then
            echo -e "\033[1;33m⚠ ter doctor:\033[0m $diffs repo↔runtime drift(s) — run \`ter doctor\` for detail."
        fi
        # Secrets check: warn on vars listed in template but unset in environment.
        if [ -f "${TER_REPO_DIR:-$HOME/ter}/secrets.template" ]; then
            local unset_n=0 missing_vars=""
            while IFS= read -r line; do
                local var="${line%%=*}"
                [ -z "$var" ] && continue
                if [ -z "$(printenv "$var" 2>/dev/null)" ]; then
                    unset_n=$((unset_n+1))
                    missing_vars="$missing_vars $var"
                fi
            done < <(grep -E '^[A-Z_][A-Z0-9_]*=' "${TER_REPO_DIR:-$HOME/ter}/secrets.template")
            if [ "$unset_n" -gt 0 ]; then
                if [ "$quiet" -eq 0 ]; then
                    echo -e "\n  \033[1;33m⚠ $unset_n secret(s) unset:\033[0m$missing_vars"
                    echo -e "    Edit ~/.config/ter/secrets.env (copy from secrets.template)."
                fi
            fi
        fi
        # Services health check
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
                fi
            fi
        fi
        [ "$quiet" -eq 0 ] && echo ""
        return
    fi

    # Reverse drift: copy drifted runtime files back into the repo.
    if [ "$1" = "sync" ]; then
        local repo="${TER_REPO_DIR:-$HOME/ter}"
        local live="$HOME/.shell.d"
        local count=0 apply=0
        [ "${2:-}" = "--yes" ] || [ "${2:-}" = "-y" ] && apply=1

        echo -e "\n\033[1;36m  🔄 TER Sync — runtime → repo\033[0m"
        local pending_from=()

        for dir in core network user docs; do
            [ -d "$live/$dir" ] || continue
            while IFS= read -r -d "" f; do
                rel="${f#$live/$dir/}"
                _ter_is_ignored "$dir/$rel" && continue
                src="$repo/$dir/$rel"
                if [ ! -e "$src" ]; then
                    pending_from+=("$f")
                    echo "  [new script]  $dir/$rel"
                    count=$((count+1))
                elif ! cmp -s "$f" "$src"; then
                    pending_from+=("$f")
                    echo "  [updated]     $dir/$rel"
                    count=$((count+1))
                fi
            done < <(find "$live/$dir" -type f -print0 2>/dev/null)
        done

        if [ "$count" -eq 0 ]; then
            echo -e "  \033[1;32m✓ Everything in sync! No unignored custom scripts found.\033[0m\n"
            return 0
        fi

        if [ "$apply" -eq 0 ]; then
            echo ""
            local confirm=""
            read -p "  Sync these $count file(s) into your ~/ter git repo? [y/N]: " confirm
            case "$confirm" in
                y|Y|yes|YES) apply=1 ;;
                *) echo -e "  \033[1;33mSync cancelled. No repo files changed.\033[0m\n"; return 0 ;;
            esac
        fi

        local sync_lock="$HOME/.config/ter/sync.lock"
        local lock_pid="" owner_pid
        owner_pid=$(sh -c 'printf "%s\n" "$PPID"')
        if ! mkdir "$sync_lock" 2>/dev/null; then
            lock_pid=$(cat "$sync_lock/pid" 2>/dev/null || true)
            if [[ "$lock_pid" =~ ^[0-9]+$ ]] && [ "$lock_pid" != "$owner_pid" ] \
                && kill -0 "$lock_pid" 2>/dev/null; then
                echo "  Another ter sync is running (pid $lock_pid)." >&2
                return 1
            fi
            rm -f "$sync_lock/pid"
            if ! rmdir "$sync_lock" 2>/dev/null || ! mkdir "$sync_lock"; then
                echo "  Cannot acquire sync lock: $sync_lock" >&2
                return 1
            fi
        fi
        printf '%s\n' "$owner_pid" > "$sync_lock/pid"

        # Isolate traps from the interactive shell. EXIT cleanup also releases
        # the lock after Ctrl-C, termination, or an unexpected copy failure.
        (
            _ter_sync_cleanup() {
                if [ "$(cat "$sync_lock/pid" 2>/dev/null || true)" = "$owner_pid" ]; then
                    rm -f "$sync_lock/pid"
                    rmdir "$sync_lock" 2>/dev/null || true
                fi
            }
            trap _ter_sync_cleanup EXIT
            trap 'exit 129' HUP
            trap 'exit 130' INT
            trap 'exit 143' TERM

            local f src rel dest_dir dest_real expected_dir repo_real tmp failures=0
            repo_real=$(cd -P "$repo" 2>/dev/null && pwd) || {
                echo "  Cannot resolve repository root: $repo" >&2
                exit 1
            }
            for f in "${pending_from[@]}"; do
                rel="${f#$live/}"
                src="$repo/$rel"
                dest_dir=$(dirname "$src")

                if [ -L "$src" ]; then
                    echo "  ✗ refused symlink target  $rel" >&2
                    failures=$((failures+1))
                    continue
                fi
                if ! mkdir -p "$dest_dir"; then
                    echo "  ✗ cannot create target directory  $dest_dir" >&2
                    failures=$((failures+1))
                    continue
                fi
                dest_real=$(cd -P "$dest_dir" 2>/dev/null && pwd) || dest_real=""
                expected_dir="$repo_real/${rel%/*}"
                if [ "$dest_real" != "$expected_dir" ]; then
                    echo "  ✗ refused symlinked target directory  $rel" >&2
                    failures=$((failures+1))
                    continue
                fi
                src="$dest_real/${rel##*/}"
                if [ -L "$src" ]; then
                    echo "  ✗ refused symlink target  $rel" >&2
                    failures=$((failures+1))
                    continue
                fi
                tmp=$(mktemp "$dest_real/.ter-sync.XXXXXX") || {
                    echo "  ✗ cannot stage  $rel" >&2
                    failures=$((failures+1))
                    continue
                }
                if cp -p "$f" "$tmp" && mv -f "$tmp" "$src"; then
                    echo "  ✓ copied  $rel -> $src"
                else
                    rm -f "$tmp"
                    echo "  ✗ failed  $rel" >&2
                    failures=$((failures+1))
                fi
            done

            if [ "$failures" -gt 0 ]; then
                echo -e "  \033[1;31m✗ $failures of $count file(s) failed; successful files remain synced.\033[0m\n" >&2
                exit 1
            fi
            echo -e "  \033[1;32m✓ $count file(s) synced with atomic file replacement to $repo.\033[0m\n"
        )
        return $?
    fi

    # Diagnostic snapshot of the current device.
    if [ "$1" = "snapshot" ]; then
        local out="${TER_REPO_DIR:-$HOME/ter}/device.lock"
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
            [ -f "${TER_REPO_DIR:-$HOME/ter}/packages.txt" ] && grep -vE '^\s*(#|$)' "${TER_REPO_DIR:-$HOME/ter}/packages.txt" | sort -u
            echo ""
            echo "## ter required NOT installed"
            if [ -f "${TER_REPO_DIR:-$HOME/ter}/packages.txt" ] && command -v pkg >/dev/null 2>&1; then
                want=$(grep -vE '^\s*(#|$)' "${TER_REPO_DIR:-$HOME/ter}/packages.txt" | sort -u)
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
        local repo="${TER_REPO_DIR:-$HOME/ter}"
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
        if [ ! -f "$sec_file" ] && [ -f "${TER_REPO_DIR:-$HOME/ter}/secrets.template" ]; then
            mkdir -p "$sec_dir"
            cp "${TER_REPO_DIR:-$HOME/ter}/secrets.template" "$sec_file"
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
        local repo="${TER_REPO_DIR:-$HOME/ter}"
        echo -e "\n\033[1;36m  ⬇  TER Update\033[0m"
        ( cd "$repo" && git pull --ff-only ) || { echo "git pull failed"; return 1; }
        ( cd "$repo" && bash install.sh ) || return 1
        echo -e "  \033[1;32m✓ Updated. Run 're' or open a new terminal.\033[0m\n"
        return
    fi

    # Open Android permission screens Termux needs for widget/shortcut foreground.
    if [ "$1" = "perms" ]; then
        echo -e "\n\033[1;36m  🔐 TER Perms — foreground unlock for widget/shortcut taps\033[0m"
        echo -e "\033[1;36m  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
        echo -e "  Widget shortcuts (~/.shortcuts/) can only open Termux in the"
        echo -e "  foreground if BOTH of these are granted:"
        echo ""
        echo -e "  \033[1;33m1) Android: Display over other apps\033[0m"
        echo -e "     Bypasses Background Activity Launch (BAL) restrictions."
        echo -e "     → grant the \033[1;37mtoggle for Termux\033[0m in the screen that just opened."
        am start -a android.settings.action.MANAGE_OVERLAY_PERMISSION -d package:com.termux >/dev/null 2>&1 \
            || am start -a android.settings.action.MANAGE_OVERLAY_PERMISSION >/dev/null 2>&1
        echo ""
        read -p "  Press Enter after granting overlay permission... " _
        echo ""
        echo -e "  \033[1;33m2) ColorOS: Allow background pop-up / start\033[0m"
        echo -e "     ColorOS/OxygenOS adds a second BAL wall on top of Google's."
        echo -e "     → in Termux app details: \033[1;37mManage permissions\033[0m →"
        echo -e "       \033[1;37mAllow background activities\033[0m (name varies by OS version)."
        am start -a android.settings.APPLICATION_DETAILS_SETTINGS -d package:com.termux >/dev/null 2>&1
        echo ""
        read -p "  Press Enter after configuring background start... " _
        echo ""
        echo -e "  \033[1;33m3) Battery optimization: don't optimize Termux\033[0m"
        echo -e "     Prevents ColorOS from killing Termux mid-tap. Without this,"
        echo -e "     widget taps land on a dead process and no-op silently."
        am start -a android.settings.IGNORE_BATTERY_OPTIMIZATION_SETTINGS >/dev/null 2>&1
        echo ""
        read -p "  Press Enter after whitelisting Termux from battery optimization... " _
        echo ""
        echo -e "  \033[1;33m4) Notification permission (Android 13+)\033[0m"
        echo -e "     Termux:Widget uses a foreground service that needs a"
        echo -e "     notification channel. Missing = service can't start."
        am start -a android.settings.APP_NOTIFICATION_SETTINGS --es android.provider.extra.APP_PACKAGE com.termux >/dev/null 2>&1
        echo ""
        echo -e "  \033[1;32m✓ With all four granted, widget taps reliably foreground Termux\033[0m"
        echo -e "  \033[1;32m  and background \`am start\`/service calls succeed.\033[0m"
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

    # Create/list/remove Home Screen Shortcuts (via Termux:Widget).
    if [ "$1" = "shortcut" ]; then
        # ter shortcut list
        if [ "$2" = "list" ] || [ "$2" = "ls" ]; then
            local dir="$HOME/.shortcuts" f n cmd_line
            echo -e "\n\033[1;36m  📱 Shortcuts in ~/.shortcuts/\033[0m"
            if [ ! -d "$dir" ] || [ -z "$(ls -A "$dir" 2>/dev/null)" ]; then
                echo "  (none)"
                echo ""
                return 0
            fi
            for f in "$dir"/*; do
                [ -f "$f" ] || continue
                n=$(basename "$f")
                # `ter shortcut` writes a line: `echo -e "  \e[37mCommand: <cmd>\e[0m\n"` — parse that.
                cmd_line=$(sed -n 's/^echo -e "  \\e\[37mCommand: \(.*\)\\e\[0m\\n"$/\1/p' "$f" 2>/dev/null | head -1)
                printf "  \033[1;33m%-20s\033[0m %s\n" "$n" "${cmd_line:-<custom / hand-edited>}"
            done
            echo ""
            return 0
        fi

        # ter shortcut rm <name>
        if [ "$2" = "rm" ] || [ "$2" = "remove" ] || [ "$2" = "del" ]; then
            local n="$3"
            if ! _ter_safe_shortcut_name "$n"; then
                echo "Shortcut name must use only letters, digits, dot, underscore, or hyphen."
                return 1
            fi
            local f="$HOME/.shortcuts/$n"
            if [ ! -e "$f" ]; then
                echo -e "  \033[1;33m✗ Not found:\033[0m $f"
                return 1
            fi
            rm -f "$f"
            echo -e "  \033[1;32m✓ Removed:\033[0m ~/.shortcuts/$n"
            return 0
        fi

        if [ -n "$2" ]; then
            local name="$2"
            if ! _ter_safe_shortcut_name "$name"; then
                echo "Shortcut name must use only letters, digits, dot, underscore, or hyphen."
                return 1
            fi
            shift 2
            # Parse optional flags: --silent skips the "Press Enter to exit" tail.
            local silent=0
            local args=()
            local a
            for a in "$@"; do
                case "$a" in
                    --silent|-s) silent=1 ;;
                    *) args+=("$a") ;;
                esac
            done
            local cmd="${args[*]}"
            if [ -z "$cmd" ]; then
                echo "Usage: ter shortcut <name> [--silent] <command>"
                echo "       ter shortcut list"
                echo "       ter shortcut rm <name>"
                echo "Example: ter shortcut adb-wizard adbcon"
                return 1
            fi

            mkdir -p "$HOME/.shortcuts"

            # Build the script. Termux:Widget foregrounds Termux on tap
            # (user gesture), so no BAL bypass hop is needed.
            local tail_block
            if [ "$silent" -eq 1 ]; then
                tail_block=''
            else
                tail_block=$'\necho -e "\\n\\e[1;32m✔ Execution finished.\\e[0m"\necho -ne "Press Enter to exit..."\nread -r'
            fi
            cat > "$HOME/.shortcuts/$name" << EOF
#!/data/data/com.termux/files/usr/bin/bash
# Generated by 'ter shortcut' on $(date -Iseconds)
# Termux:Widget foregrounds Termux on tap; native \`am\` (termux-am) handles intents.
[ -f "\$HOME/.bashrc" ] && source "\$HOME/.bashrc" >/dev/null 2>&1
termux-toast "Running shortcut: $name..." 2>/dev/null
echo -e "🚀 \e[1;36mRunning: $name\e[0m"
echo -e "  \e[37mCommand: $cmd\e[0m\n"
$cmd${tail_block}
EOF
            chmod +x "$HOME/.shortcuts/$name"
            echo -e "✅ \033[1;32mCreated shortcut:\033[0m ~/.shortcuts/$name$([ "$silent" -eq 1 ] && echo " (silent)")"

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
        echo "Usage: ter shortcut <name> [--silent] <command>"
        echo "       ter shortcut list"
        echo "       ter shortcut rm <name>"
        echo ""
        echo "Examples:"
        echo "  ter shortcut adb-wizard adbcon"
        echo "  ter shortcut sys-info adb-sysinfo"
        echo "  ter shortcut dvop-off --silent 'dvop off -f -s'"
        echo ""
        echo "Flags:"
        echo "  --silent, -s   Skip 'Press Enter to exit' tail (fire-and-forget)."
        echo ""
        echo "Note: Requires the 'Termux:Widget' app installed on your phone."
        return 0
    fi

    # Handle theme selection
    if [ "$1" = "theme" ]; then
        if [ "$2" = "next" ] || [ "$2" = "rotate" ]; then
            _ter_theme_next
            return
        fi
        if [ -n "$2" ]; then
            _ter_set_theme "$2"
            return
        fi

        # Interactive Menu
        echo -e "\n\033[1;36m  🎨 TER OS Theme Switcher\033[0m"
        echo -e "\033[1;36m  ━━━━━━━━━━━━━━━━━━━━━━\033[0m"
        echo "  [C] Solarized & Sage Green        [H] Aubergine Wine & Peach Cream"
        echo "  [F] Midnight Indigo & Soft Lavender  [I] Obsidian Black & Amber Gold"
        echo "  [G] Charcoal Coffee & Warm Sand   [J] Nord Frost & Glacier Blue"
        echo "  [K] Ocean Deep & Aqua Glow        [L] Rose Quartz & Blush Pink"
        echo "  [M] Matrix Emerald & Neon Lime    [N] Sunset Ember & Coral Bloom"
        echo ""
        echo "  [R] Rotate to next theme"
        echo ""
        read -p "Select theme [C-N/R]: " choice
        case "$choice" in
            R|r)
                _ter_theme_next
                ;;
            "")
                echo "No changes made."
                return
                ;;
            *)
                if ! _ter_set_theme "$choice"; then
                    echo "No changes made."
                    return
                fi
                ;;
        esac
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
