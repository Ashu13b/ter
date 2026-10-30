# ── AirLink: Universal Cross-Device Auth Bridge & URL Toolkit ──
# Bridges CLI sessions across devices (Termux, remote VM, other phone),
# serves an ephemeral mobile auth gateway, heals soft-wrapped URLs, and
# extracts authorization codes seamlessly.

airlink() {
    local script="$HOME/.shell.d/user/airlink.py"
    if [ ! -f "$script" ]; then
        script="$HOME/ter/user/airlink.py"
    fi
    if [ ! -f "$script" ]; then
        echo "airlink: core script not found." >&2
        return 1
    fi
    python3 "$script" "$@"
}

# Standalone Link Healer
url-heal() {
    local script="$HOME/.shell.d/user/airlink.py"
    if [ ! -f "$script" ]; then
        script="$HOME/ter/user/airlink.py"
    fi
    python3 "$script" heal "$@"
}

# Standalone Terminal QR Generator
qr() {
    local script="$HOME/.shell.d/user/airlink.py"
    if [ ! -f "$script" ]; then
        script="$HOME/ter/user/airlink.py"
    fi
    python3 "$script" qr "$@"
}

# Standalone Auth Code Extractor
auth-code() {
    local script="$HOME/.shell.d/user/airlink.py"
    if [ ! -f "$script" ]; then
        script="$HOME/ter/user/airlink.py"
    fi
    python3 "$script" code "$@"
}

# Shell completions for Bash & Zsh
if [ -n "${BASH_VERSION:-}" ]; then
    _ter_airlink_completions() {
        local cur prev
        cur="${COMP_WORDS[COMP_CWORD]}"
        prev="${COMP_WORDS[COMP_CWORD-1]}"
        local nodes="ubu oracle my-tablet"
        if [ -f "$HOME/.ssh/config" ]; then
            nodes=$(grep -E '^Host ' "$HOME/.ssh/config" | grep -v '\*' | awk '{$1=""; print $0}')
        fi
        local common_cmds="agy gh claude tailscale jupyter gcloud code"
        local flags="--qr --open --clip --local --no-save -h --help"
        if [ "$COMP_CWORD" -eq 1 ]; then
            COMPREPLY=($(compgen -W "$nodes $common_cmds $flags" -- "$cur"))
        elif [ "$COMP_CWORD" -eq 2 ]; then
            COMPREPLY=($(compgen -W "$common_cmds $flags" -- "$cur"))
        fi
    }
    complete -F _ter_airlink_completions airlink 2>/dev/null || true
elif [ -n "${ZSH_VERSION:-}" ]; then
    _ter_zsh_airlink() {
        local -a nodes common_cmds
        if [ -f "$HOME/.ssh/config" ]; then
            nodes=($(grep -E '^Host ' "$HOME/.ssh/config" | grep -v '\*' | awk '{$1=""; print $0}'))
        fi
        common_cmds=(
            'agy:Antigravity CLI'
            'gh:GitHub CLI'
            'claude:Claude Code CLI'
            'tailscale:Tailscale VPN'
            'jupyter:Jupyter Notebook server'
            'gcloud:Google Cloud SDK'
        )
        if (( CURRENT == 2 )); then
            _describe 'node or command' nodes -- common_cmds
        fi
    }
    if type compdef >/dev/null 2>&1; then
        compdef _ter_zsh_airlink airlink 2>/dev/null || true
    fi
fi
