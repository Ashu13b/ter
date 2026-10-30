# ── Antigravity CLI Account Switcher & Rotator Module ──
# Wraps agy-account.py to manage multiple Antigravity sessions/tokens.

agy-account() {
    local script="$HOME/.shell.d/user/agy-account.py"
    [ -f "$script" ] || script="${TER_REPO_DIR:-$HOME/ter}/user/agy-account.py"
    if [ ! -f "$script" ]; then
        echo "agy-account: script not found ($script)" >&2
        return 1
    fi
    python3 "$script" "$@"
}

# Subcommand interceptor: 'agy account ...' routes to agy-account
agy() {
    if [ "$#" -gt 0 ] && { [ "$1" = "account" ] || [ "$1" = "accounts" ]; }; then
        shift
        agy-account "$@"
    else
        command agy "$@"
    fi
}

# Handy shortcuts
alias agy-ac='agy-account'
alias agy-next='agy-account next'
alias agy-ls='agy-account list'

# Shell completions (Bash & Zsh)
if [ -n "${BASH_VERSION:-}" ]; then
    _ter_agy_account_completions() {
        local cur prev
        cur="${COMP_WORDS[COMP_CWORD]}"
        prev="${COMP_WORDS[COMP_CWORD-1]}"
        local subcmds="list status ls save add switch use next rotate rm remove delete sync sync-phone -h --help"
        if [ "$COMP_CWORD" -eq 1 ]; then
            COMPREPLY=($(compgen -W "$subcmds" -- "$cur"))
            return 0
        fi
        case "$prev" in
            switch|use|rm|remove|delete)
                local accounts_dir="${AGY_DIR:-$HOME/.gemini/antigravity-cli}/accounts"
                if [ -d "$accounts_dir" ]; then
                    local accts
                    accts=$(ls -1 "$accounts_dir" 2>/dev/null)
                    COMPREPLY=($(compgen -W "$accts" -- "$cur"))
                fi
                return 0
                ;;
        esac
    }
    complete -F _ter_agy_account_completions agy-account 2>/dev/null || true
elif [ -n "${ZSH_VERSION:-}" ]; then
    _ter_zsh_agy_account() {
        local -a subcmds
        subcmds=(
            'list:List all saved accounts and active status'
            'save:Save current session under alias'
            'switch:Switch active session to specified account'
            'next:Rotate to next saved account (round-robin)'
            'rm:Remove a saved account profile'
            'sync:Sync all saved accounts to remote host'
            'sync-phone:Sync all saved accounts to remote phone'
        )
        if (( CURRENT == 2 )); then
            _describe 'subcommand' subcmds
        elif (( CURRENT == 3 )); then
            case "$words[2]" in
                switch|use|rm|remove|delete)
                    local accounts_dir="${AGY_DIR:-$HOME/.gemini/antigravity-cli}/accounts"
                    if [ -d "$accounts_dir" ]; then
                        local -a accts
                        accts=($(ls -1 "$accounts_dir" 2>/dev/null))
                        _describe 'account' accts
                    fi
                    ;;
            esac
        fi
    }
    if type compdef >/dev/null 2>&1; then
        compdef _ter_zsh_agy_account agy-account 2>/dev/null || true
    fi
fi
