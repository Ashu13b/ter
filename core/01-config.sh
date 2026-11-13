export TER_VERSION="1.4"
export TNL_REMOTE="ubu"; export TNL_DEF_FSERVER_PORT="6000"
export NET_CHECK_TARGET="8.8.8.8"; export NET_CHECK_PORT="80"

# Shell Identity
export MY_NAME="Ashish Yadav"
[ -n "${ZSH_VERSION:-}" ] && export CURRENT_SHELL="zsh"
[ -n "${BASH_VERSION:-}" ] && export CURRENT_SHELL="bash"

# Protected Ports
export TNL_PROTECTED_PORTS="22 8022 443"

# Ensure Termux DNS resolver and hosts are populated for glibc & Go CLIs (agy, codext)
_ter_heal_dns() {
    [ -n "${PREFIX:-}" ] && [ -d "$PREFIX/etc" ] || return 0
    local etc_dir="$PREFIX/etc"
    if [ ! -s "$etc_dir/resolv.conf" ] || ! grep -q "nameserver" "$etc_dir/resolv.conf" 2>/dev/null; then
        cat << 'EOF' > "$etc_dir/resolv.conf" 2>/dev/null || true
nameserver 1.1.1.1
nameserver 8.8.8.8
nameserver 1.0.0.1
nameserver 8.8.4.4
options timeout:2 attempts:2
EOF
    fi

    # Symlink to glibc/etc if present
    if [ -d "$PREFIX/glibc/etc" ]; then
        [ -e "$PREFIX/glibc/etc/resolv.conf" ] || ln -sf "$etc_dir/resolv.conf" "$PREFIX/glibc/etc/resolv.conf" 2>/dev/null || true
        [ -e "$PREFIX/glibc/etc/hosts" ] || ln -sf "$etc_dir/hosts" "$PREFIX/glibc/etc/hosts" 2>/dev/null || true
    fi

    # Auto-resolve Google API hosts via Android Bionic socket into /etc/hosts to bypass UDP 53 blocking
    if [ ! -f "$etc_dir/hosts" ] || ! grep -q "oauth2.googleapis.com" "$etc_dir/hosts" 2>/dev/null; then
        if command -v python3 >/dev/null 2>&1; then
            python3 -c '
import socket
from pathlib import Path
h = Path("'"$etc_dir"'/hosts")
content = h.read_text() if h.exists() else "127.0.0.1 localhost\n::1 ip6-localhost\n"
domains = ["oauth2.googleapis.com", "accounts.google.com", "cloudaicompanion.googleapis.com", "generativelanguage.googleapis.com", "cloudresourcemanager.googleapis.com", "iam.googleapis.com"]
new_lines = []
for d in domains:
    if d not in content:
        try:
            ip = socket.gethostbyname(d)
            new_lines.append(f"{ip} {d}")
        except Exception:
            pass
if new_lines:
    with open(h, "a") as f:
        f.write("\n# Auto-resolved Google API hosts for glibc/Go network stability\n" + "\n".join(new_lines) + "\n")
' 2>/dev/null || true
        fi
    fi
}
_ter_heal_dns

# Let TER's tab-title logic (tab_title.sh) control the terminal/session name.
# These CLIs would otherwise overwrite it while running. codex has no env var —
# disable via `[tui] terminal_title = []` in ~/.codex/config.toml.
export OPENCODE_DISABLE_TERMINAL_TITLE=1
export CLAUDE_CODE_DISABLE_TERMINAL_TITLE=1

# Parse startup preferences as data, never as shell code. Keeping this in the
# early core layer lets later startup modules reuse one fast, validated read.
_ter_load_startup_config() {
    local startup_file="$HOME/.config/ter/startup.conf"
    local key value extra
    TMUX_AUTOSTART=true
    WELCOME_DASHBOARD=true
    OPTIMIZE_STATUS=false
    [ -f "$startup_file" ] || return 0
    while IFS='=' read -r key value extra || [ -n "$key" ]; do
        [ -z "${extra:-}" ] || continue
        case "$key:$value" in
            TMUX_AUTOSTART:true|TMUX_AUTOSTART:false) TMUX_AUTOSTART="$value" ;;
            WELCOME_DASHBOARD:true|WELCOME_DASHBOARD:false) WELCOME_DASHBOARD="$value" ;;
            OPTIMIZE_STATUS:true|OPTIMIZE_STATUS:false) OPTIMIZE_STATUS="$value" ;;
        esac
    done < "$startup_file"
    export TMUX_AUTOSTART WELCOME_DASHBOARD OPTIMIZE_STATUS
}
_ter_load_startup_config

# Secrets — load env vars from ~/.config/ter/secrets.env if present.
# Template lives at ~/ter/secrets.template (copy + fill, never commit values).
if [ -f "$HOME/.config/ter/secrets.env" ]; then
    set -a
    . "$HOME/.config/ter/secrets.env"
    set +a
fi
