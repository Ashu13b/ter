# ── Universal Remote URL Capturer & Local Browser Opener ──
# Runs any CLI command on a remote VM, captures any login/auth URL
# (Google, GitHub, Claude, Tailscale, Jupyter, etc.), and opens it locally on your phone.

remurl() {
    if [ "$#" -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ] || [ "$1" = "help" ]; then
        echo -e "\033[1;36mremurl: Universal Remote URL Capturer & Local Opener\033[0m"
        echo ""
        echo "Runs any CLI command on your remote VM (e.g. ubu / oracle), captures any"
        echo "authentication/login/service URL (Google, GitHub, Claude, Tailscale, Jupyter, etc.),"
        echo "and opens it instantly on your phone browser while keeping the session interactive."
        echo ""
        echo "Usage:"
        echo "  remurl <command...>                Run command on default active node (e.g. ubu)"
        echo "  remurl <node> <command...>         Run command on specific node (e.g. oracle, ubu)"
        echo "  remurl --tmux <command...>         Run inside remote tmux session and attach (for TUI apps)"
        echo "  remurl --no-open <command...>      Print captured URL without opening in browser"
        echo ""
        echo "Examples:"
        echo "  remurl gh auth login               GitHub device flow"
        echo "  remurl claude login                Anthropic Claude CLI login"
        echo "  remurl tailscale up                Tailscale node authentication"
        echo "  remurl jupyter notebook            Jupyter token capture"
        echo "  remurl oracle gcloud auth login    Explicit node target"
        echo "  remurl --tmux agy                  Antigravity full-screen TUI"
        return 0
    fi

    if command -v nx >/dev/null 2>&1; then
        nx url-open "$@"
    elif [ -f "$HOME/nexus/nexus.py" ]; then
        python3 "$HOME/nexus/nexus.py" url-open "$@"
    else
        echo "remurl requires NEXUS (~/nexus/nexus.py)." >&2
        return 1
    fi
}

# Shell completions for Bash & Zsh
if [ -n "${BASH_VERSION:-}" ]; then
    _ter_remurl_completions() {
        local cur prev
        cur="${COMP_WORDS[COMP_CWORD]}"
        prev="${COMP_WORDS[COMP_CWORD-1]}"
        local nodes="ubu oracle my-tablet"
        if [ -f "$HOME/.ssh/config" ]; then
            nodes=$(grep -E '^Host ' "$HOME/.ssh/config" | grep -v '\*' | awk '{$1=""; print $0}')
        fi
        local common_cmds="gh claude tailscale jupyter agy gcloud huggingface-cli code"
        if [ "$COMP_CWORD" -eq 1 ]; then
            COMPREPLY=($(compgen -W "$nodes $common_cmds --tmux --no-open -h --help" -- "$cur"))
        elif [ "$COMP_CWORD" -eq 2 ]; then
            COMPREPLY=($(compgen -W "$common_cmds" -- "$cur"))
        fi
    }
    complete -F _ter_remurl_completions remurl 2>/dev/null || true
elif [ -n "${ZSH_VERSION:-}" ]; then
    _ter_zsh_remurl() {
        local -a nodes common_cmds
        if [ -f "$HOME/.ssh/config" ]; then
            nodes=($(grep -E '^Host ' "$HOME/.ssh/config" | grep -v '\*' | awk '{$1=""; print $0}'))
        fi
        common_cmds=(
            'gh:GitHub CLI'
            'claude:Claude Code CLI'
            'tailscale:Tailscale VPN'
            'jupyter:Jupyter Notebook server'
            'agy:Antigravity CLI'
            'gcloud:Google Cloud SDK'
        )
        if (( CURRENT == 2 )); then
            _describe 'node or command' nodes -- common_cmds
        fi
    }
    if type compdef >/dev/null 2>&1; then
        compdef _ter_zsh_remurl remurl 2>/dev/null || true
    fi
fi
