#!/bin/bash

# ── Dynamic Session Tab Naming ──
# Renames the Termux session tab shown in the drawer/side-panel.

export DISABLE_AUTO_TITLE="true"

_ter_set_title() {
    local title="$1"
    if [ -n "$ZSH_VERSION" ]; then
        (
            sleep 0.1
            printf "\e]0;%s\a" "${title}"
        ) < /dev/null 2>/dev/null &!
    else
        (
            sleep 0.1
            printf "\e]0;%s\a" "${title}"
        ) < /dev/null 2>/dev/null &
        disown $! 2>/dev/null || true
    fi
}

_ter_get_folder() {
    local folder; folder=$(basename "$PWD")
    [ "$folder" = "files" ] && folder="home"
    echo "$folder"
}

tabname() {
    if [ -n "$*" ]; then
        export MANUAL_TAB_NAME="$*"
    else
        export MANUAL_TAB_NAME=""
    fi
    _ter_precmd_title
}

_ter_precmd_title() {
    if [ -n "$MANUAL_TAB_NAME" ]; then
        _ter_set_title "$MANUAL_TAB_NAME"
        return
    fi
    local prefix=""
    [ -n "$NEXUS_SERVICE_NAME" ] && prefix="$NEXUS_SERVICE_NAME:"
    
    local env_prefix="u"
    [ "$(uname -o 2>/dev/null)" = "Android" ] && env_prefix="t"
    
    _ter_set_title "${env_prefix}:${prefix}$(_ter_get_folder)"
}

_ter_preexec_title() {
    if [ -n "$MANUAL_TAB_NAME" ]; then return; fi
    
    local cmd="$1"
    local cmd_name="${cmd%% *}"
    local prefix=""
    [ -n "$NEXUS_SERVICE_NAME" ] && prefix="$NEXUS_SERVICE_NAME:"
    
    local env_prefix="u"
    [ "$(uname -o 2>/dev/null)" = "Android" ] && env_prefix="t"
    
    _ter_set_title "${env_prefix}:${prefix}$(_ter_get_folder)⟩$cmd_name"
}

if [ -n "$ZSH_VERSION" ]; then
    autoload -Uz add-zsh-hook 2>/dev/null
    add-zsh-hook precmd _ter_precmd_title 2>/dev/null
    add-zsh-hook preexec _ter_preexec_title 2>/dev/null
else
    # Bash fallback
    PROMPT_COMMAND="_ter_precmd_title; $PROMPT_COMMAND"
fi
