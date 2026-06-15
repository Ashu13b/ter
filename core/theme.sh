# ── TER HUD Prompt (Dynamic Theme S2 Trench) ──

# Load dynamic colors if they exist, fallback to Nord blue (4) and Green (2)
[ -f ~/.shell.d/core/theme_colors.sh ] && source ~/.shell.d/core/theme_colors.sh
L_CLR=${TER_P_LINE:-4}
A_CLR=${TER_P_ACCENT:-2}

_p_git() {
    local branch; branch=$(git branch --show-current 2>/dev/null)
    [ -n "$branch" ] && echo -e " %F{36}◈%f %F{5}$branch%f" || true
}

if [ -n "$ZSH_VERSION" ]; then
    setopt PROMPT_SUBST
    PROMPT='%B%F{$L_CLR}▬▬ %f%F{36}ᴛᴇʀ%f$(_p_git) %F{$L_CLR}▬▬%f %F{6}%~%f
%F{$A_CLR}➤%f%b '
elif [ -n "$BASH_VERSION" ]; then
    _b_git() {
        local b; b=$(git branch --show-current 2>/dev/null)
        [ -n "$b" ] && echo -e " \e[1;36m◈\e[0m \e[1;35m$b\e[0m" || true
    }
    PS1='\n\[\e[1;34m\]▬▬ \[\e[1;36m\]ᴛᴇʀ\[\e[0m\]$(_b_git) \[\e[1;34m\]▬▬ \[\e[0;36m\]\w\[\e[0m\]\n\[\e[1;32m\]➤\[\e[0m\] '
fi

# ── Dynamic Terminal Title (Auto Session Renamer) ──
_set_terminal_title() {
    local folder; folder=$(basename "$PWD")
    [ "$folder" = "files" ] && folder="home"
    
    local title
    if [ -n "$MANUAL_TAB_NAME" ]; then
        title="ter:$MANUAL_TAB_NAME"
    else
        local prefix=""
        if [ -n "$SESSION_NAME" ]; then
            prefix="$SESSION_NAME:"
        elif [ -n "$SESSION" ]; then
            prefix="$SESSION:"
        elif [ -n "$TAB_NAME" ]; then
            prefix="$TAB_NAME:"
        elif [ -n "$NEXUS_SERVICE_NAME" ]; then  # Set by NEXUS app when running services
            prefix="$NEXUS_SERVICE_NAME:"
        fi
        title="ter:${prefix}${folder}"
    fi

    # Use ANSI escape sequence to set terminal window/tab/session title
    if [ -n "$ZSH_VERSION" ]; then
        print -n "\e]0;${title}\a"
    else
        echo -ne "\e]0;${title}\a"
    fi
}

if [ -n "$ZSH_VERSION" ]; then
    # Hook to Zsh's pre-prompt functions list
    if [[ ! " ${precmd_functions[*]} " =~ " _set_terminal_title " ]]; then
        precmd_functions+=(_set_terminal_title)
    fi
elif [ -n "$BASH_VERSION" ]; then
    # Hook to Bash's PROMPT_COMMAND
    if [ -n "$PROMPT_COMMAND" ]; then
        case ";$PROMPT_COMMAND;" in
            *";_set_terminal_title;"*) ;;
            *) PROMPT_COMMAND="_set_terminal_title; $PROMPT_COMMAND" ;;
        esac
    else
        PROMPT_COMMAND="_set_terminal_title"
    fi
fi
