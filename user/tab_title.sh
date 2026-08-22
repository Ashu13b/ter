#!/bin/bash

# ── Dynamic Session Tab Naming (Single Source of Truth) ──
# Renames the terminal / Termux session tab shown in the drawer and window title.
# Structure: [1. WHERE (Icon only)] + [2. WHO/HIJACKER (Agent/Tool)] + [3. FOLDER]

export DISABLE_AUTO_TITLE="true"

# TUI agents (e.g. opencode, claude) overwrite the tab title with their own name
# ("OpenCode" / "OC | <session>"). Tell them to leave our title alone.
export OPENCODE_DISABLE_TERMINAL_TITLE="1"
export CLAUDE_CODE_DISABLE_TERMINAL_TITLE="1"

# ── Title Output Helper ──
_ter_set_title() {
    local title="$1"
    # Strip ASCII control characters to prevent escape injection
    local clean_title
    clean_title=$(printf '%s' "$title" | tr -d '\000-\037\177')
    if [ -n "${TMUX:-}" ]; then
        tmux rename-window "${clean_title}" 2>/dev/null || true
    else
        printf '\033]0;%s\007' "${clean_title}"
    fi
}

# ── Persistent Title Watch ──
# Long-running TUIs can still clobber the title (e.g. opencode blanks it on
# renderer init). Re-assert our title on an interval while the app runs; the
# next prompt (precmd) stops the loop.
_TER_TITLE_WATCH_PID=""

_ter_watch_loop() {
    local title="$1"
    local ppid="$$"
    while kill -0 "$ppid" 2>/dev/null; do
        sleep 2
        _ter_set_title "$title"
    done
}

_ter_start_title_watch() {
    _ter_stop_title_watch
    case $- in
        *i*) ;;
        *) return ;;
    esac
    _ter_watch_loop "$1" &
    _TER_TITLE_WATCH_PID=$!
    disown "$_TER_TITLE_WATCH_PID" 2>/dev/null || true
}

_ter_stop_title_watch() {
    if [ -n "${_TER_TITLE_WATCH_PID:-}" ]; then
        kill "$_TER_TITLE_WATCH_PID" 2>/dev/null || true
        _TER_TITLE_WATCH_PID=""
    fi
}

# ── Manual Override ──
tabname() {
    if [ -n "$*" ]; then
        export MANUAL_TAB_NAME="$*"
    else
        export MANUAL_TAB_NAME=""
    fi
    _ter_precmd_title
}

# ── Environment & Host Icon Resolver ──
_ter_icon_for_env() {
    local target="$1"
    local target_lower
    target_lower=$(printf '%s' "$target" | tr '[:upper:]' '[:lower:]')

    case "$target_lower" in
        *oracle*|*ubu*|*cld*|*cloud*|*vps*|*aws*|*gcp*|*oci*|*server*)
            echo "☁️"
            ;;
        *laptop*|*pc*|*desktop*|*mac*|*book*|*thinkpad*|*workstation*)
            echo "💻"
            ;;
        *tablet*|*tab*|*pad*)
            echo "📱"
            ;;
        phone|termux|local|android)
            echo "📱"
            ;;
        ssh*)
            local host="${target_lower#ssh:}"
            case "$host" in
                *oracle*|*ubu*|*cld*|*cloud*|*vps*|*aws*|*gcp*|*oci*|*server*)
                    echo "☁️"
                    ;;
                *laptop*|*pc*|*desktop*|*mac*|*book*|*thinkpad*|*workstation*)
                    echo "💻"
                    ;;
                *tablet*|*tab*|*pad*)
                    echo "📱"
                    ;;
                *)
                    echo "☁️"
                    ;;
            esac
            ;;
        *)
            if [ "$(uname -o 2>/dev/null)" = "Android" ] || [ -n "${TERMUX_VERSION:-}" ]; then
                echo "📱"
            else
                echo "💻"
            fi
            ;;
    esac
}

# ── Host / Node Identity ──
_ter_where() {
    if [ -n "${SSH_CONNECTION:-}" ] || [ -n "${SSH_CLIENT:-}" ]; then
        local remote_h="${HOSTNAME:-}"
        [ -z "$remote_h" ] && remote_h=$(hostname -s 2>/dev/null || uname -n 2>/dev/null || echo "remote")
        remote_h="${remote_h%%.*}"
        echo "ssh:${remote_h}"
    elif [ "$(uname -o 2>/dev/null)" = "Android" ] || [ -n "${TERMUX_VERSION:-}" ]; then
        echo "phone"
    else
        local host_short
        host_short="${HOSTNAME:-}"
        [ -z "$host_short" ] && host_short=$(hostname -s 2>/dev/null || uname -s 2>/dev/null || echo "node")
        host_short="${host_short%%.*}"
        echo "${host_short:-node}"
    fi
}

# ── Current Folder Formatter ──
# Last folder component only — full paths make drawer tabs unreadable.
_ter_short_pwd() {
    local pwd_val="${PWD:-/}"
    if [ "$pwd_val" = "$HOME" ]; then
        echo "~"
        return
    fi
    local cur="${pwd_val##*/}"
    [ -z "$cur" ] && cur="root"
    [ "$cur" = "files" ] && cur="~"
    echo "$cur"
}

# ── Strip Ubuntu/Debian default PS1 title escapes Helper ──
_ter_sanitize_ps1() {
    if [ -n "${BASH_VERSION:-}" ] && [ -n "${PS1:-}" ]; then
        if [[ "$PS1" == *"\\e]0;"* ]] || [[ "$PS1" == *"\\033]0;"* ]] || [[ "$PS1" == *$'\033]0;'* ]] || \
           [[ "$PS1" == *"\\e]2;"* ]] || [[ "$PS1" == *"\\033]2;"* ]] || [[ "$PS1" == *$'\033]2;'* ]]; then
            PS1="$(printf '%s' "$PS1" | sed -E 's/(\\\[)?(\\[eE]|\\033|\x1b)\][02];(\\.|[^\x07\x1b\\])*(\\[aA]|\x07|(\\[eE]|\\033|\x1b)\\\\)(\\\])?//g')"
        fi
    fi
}

# ── Precmd Hook: Native Shell / Idle Prompt ──
_ter_precmd_title() {
    _ter_stop_title_watch
    if [ -n "${MANUAL_TAB_NAME:-}" ]; then
        _ter_set_title "$MANUAL_TAB_NAME"
        return
    fi

    # Dynamically sanitize Ubuntu/Debian default PS1 title escapes
    _ter_sanitize_ps1

    local where; where=$(_ter_where)
    local icon; icon=$(_ter_icon_for_env "$where")
    local folder; folder=$(_ter_short_pwd)

    # Native Shell (Idle): [icon] [folder]
    _ter_set_title "${icon}/${folder}"
}

# ── Preexec Hook: Hijacked by Tool / Agent / Command ──
_ter_preexec_title() {
    if [ -n "${MANUAL_TAB_NAME:-}" ]; then return; fi

    local cmd="$1"
    cmd="${cmd#"${cmd%%[![:space:]]*}"}"
    [ -z "$cmd" ] && return

    # Strip environment variable assignments and privilege wrappers
    while [ -n "$cmd" ]; do
        local first_token="${cmd%% *}"
        case "$first_token" in
            sudo|doas|env)
                if [ "$first_token" = "$cmd" ]; then
                    cmd=""
                    break
                fi
                cmd="${cmd#* }"
                cmd="${cmd#"${cmd%%[![:space:]]*}"}"
                while [ -n "$cmd" ]; do
                    case "$cmd" in
                        -[uUgCphrTtS]|-u\ *|-U\ *|-g\ *|-C\ *|-p\ *|-h\ *|-r\ *|-t\ *|-T\ *|-S\ *)
                            cmd="${cmd#* }"
                            cmd="${cmd#"${cmd%%[![:space:]]*}"}"
                            cmd="${cmd#* }"
                            cmd="${cmd#"${cmd%%[![:space:]]*}"}"
                            ;;
                        --user\ *|--group\ *|--chdir\ *|--host\ *|--prompt\ *|--unset\ *|--split-string\ *)
                            cmd="${cmd#* }"
                            cmd="${cmd#"${cmd%%[![:space:]]*}"}"
                            cmd="${cmd#* }"
                            cmd="${cmd#"${cmd%%[![:space:]]*}"}"
                            ;;
                        --*|-*)
                            cmd="${cmd#* }"
                            cmd="${cmd#"${cmd%%[![:space:]]*}"}"
                            ;;
                        *)
                            break
                            ;;
                    esac
                done
                ;;
            [A-Za-z_]*=*)
                if [ "$first_token" = "$cmd" ]; then
                    cmd=""
                    break
                fi
                cmd="${cmd#* }"
                cmd="${cmd#"${cmd%%[![:space:]]*}"}"
                ;;
            *)
                break
                ;;
        esac
    done
    [ -z "$cmd" ] && return

    local cmd_name="${cmd%% *}"
    local cmd_arg="${cmd#* }"
    [ "$cmd_arg" = "$cmd" ] && cmd_arg=""
    cmd_arg="${cmd_arg#"${cmd_arg%%[![:space:]]*}"}"

    local where; where=$(_ter_where)
    local icon; icon=$(_ter_icon_for_env "$where")
    local folder; folder=$(_ter_short_pwd)

    case "$cmd_name" in
        # Remote SSH Hijack
        ssh|mosh)
            local host=""
            local skip_next=0
            for token in $cmd_arg; do
                if [ "$skip_next" -eq 1 ]; then
                    skip_next=0
                    continue
                fi
                case "$token" in
                    -p|-i|-l|-c|-F|-o|-b|-e|-J|-L|-R|-D|-m|-O|-S|-w|-B|-E|-I)
                        skip_next=1
                        ;;
                    -*)
                        ;;
                    *)
                        host="${token##*@}"
                        host="${host%%:*}"
                        host="${host%%.*}"
                        break
                        ;;
                esac
            done
            [ -z "$host" ] && host="remote"
            icon=$(_ter_icon_for_env "$host")
            _ter_set_title "${icon}/${host}"
            return
            ;;
        # AI Coding Agents & LLM CLIs
        # 🤖 marker makes agent-hijacked tabs instantly distinguishable from
        # plain folder tabs (agents that overwrite titles get re-asserted by
        # the watch loop with this same format).
        agy|codex|claude|aider|gemini|aichat|ai|opendevin|oc|opencode)
            local a_title="${icon}/[🤖${cmd_name}]/${folder}"
            _ter_set_title "${a_title}"
            _ter_start_title_watch "${a_title}"
            return
            ;;
        # Android Debug Bridge / Device Tools
        adb|fastboot|scrcpy)
            local subcmd=""
            local skip_next=0
            for token in $cmd_arg; do
                if [ "$skip_next" -eq 1 ]; then
                    skip_next=0
                    continue
                fi
                case "$token" in
                    -s|-p|-H|-P|-L)
                        skip_next=1
                        ;;
                    -*)
                        ;;
                    *)
                        subcmd="$token"
                        break
                        ;;
                esac
            done
            if [ -n "$subcmd" ]; then
                _ter_set_title "${icon}/${cmd_name}:${subcmd}/${folder}"
            else
                _ter_set_title "${icon}/${cmd_name}/${folder}"
            fi
            return
            ;;
        # Editors & Interactive Tools
        vim|nvim|nano|helix|code|htop|btop|top|python|python3|node|ipython)
            local file_target=""
            local skip_next=0
            for token in $cmd_arg; do
                if [ "$skip_next" -eq 1 ]; then
                    skip_next=0
                    continue
                fi
                case "$token" in
                    -u|-c|-s|-w|-W|-i)
                        skip_next=1
                        ;;
                    -*)
                        ;;
                    *)
                        file_target="${token##*/}"
                        break
                        ;;
                esac
            done
            [ -z "$file_target" ] && file_target="$folder"
            _ter_set_title "${icon}/${cmd_name}/${file_target}"
            return
            ;;
    esac

    # Generic Active Command: [icon] [cmd] / [folder]
    _ter_set_title "${icon}/${cmd_name}/${folder}"
}

# ── Strip Ubuntu/Debian default PS1 title escapes & Register Hooks ──
if [ -n "$BASH_VERSION" ]; then
    _ter_sanitize_ps1

    _TER_BASH_PREEXEC_RUN=0
    _ter_bash_preexec() {
        [ "$_TER_BASH_PREEXEC_RUN" -eq 1 ] && return
        [ -n "${COMP_LINE:-}" ] && return
        [ "$BASH_COMMAND" = "${PROMPT_COMMAND:-}" ] && return
        case "$BASH_COMMAND" in
            _ter_*|*PROMPT_COMMAND*|*MANUAL_TAB_NAME*) return ;;
        esac
        _TER_BASH_PREEXEC_RUN=1
        _ter_preexec_title "$BASH_COMMAND"
    }

    _ter_bash_precmd() {
        _TER_BASH_PREEXEC_RUN=0
        _ter_precmd_title
    }

    case ";${PROMPT_COMMAND:-};" in
        *";_ter_bash_precmd;"*|*"_ter_bash_precmd;"*) ;;
        *) PROMPT_COMMAND="_ter_bash_precmd;${PROMPT_COMMAND:-}" ;;
    esac

    case $- in
        *i*) trap '_ter_bash_preexec' DEBUG 2>/dev/null ;;
    esac
elif [ -n "$ZSH_VERSION" ]; then
    autoload -Uz add-zsh-hook 2>/dev/null
    add-zsh-hook precmd _ter_precmd_title 2>/dev/null
    add-zsh-hook preexec _ter_preexec_title 2>/dev/null
fi
