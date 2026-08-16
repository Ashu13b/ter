export TER_VERSION="1.4"
export TNL_REMOTE="ubu"; export TNL_DEF_FSERVER_PORT="6000"
export NET_CHECK_TARGET="8.8.8.8"; export NET_CHECK_PORT="80"

# Shell Identity
export MY_NAME="Ashish Yadav"
[ -n "${ZSH_VERSION:-}" ] && export CURRENT_SHELL="zsh"
[ -n "${BASH_VERSION:-}" ] && export CURRENT_SHELL="bash"

# Protected Ports
export TNL_PROTECTED_PORTS="22 8022 443"

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
