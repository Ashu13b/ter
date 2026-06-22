#!/bin/bash

# ── Dynamic Session Tab Naming ──
# Renames the Termux session tab shown in the drawer/side-panel.

export DISABLE_AUTO_TITLE="true"

_ter_set_title() {
    local title="$1"
    if [ -n "$TMUX" ]; then
        tmux rename-window "${title}" 2>/dev/null || true
    else
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
    fi
}

_ter_get_folder() {
    local folder; folder=$(basename "$PWD")
    [ "$folder" = "files" ] && folder="home"
    echo "${folder}/"
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
    _ter_set_title "${prefix}$(_ter_short_pwd)"
}

_ter_short_pwd() {
    # Show parent/child for context (e.g. "home/ter") without overflowing.
    local cur; cur=$(basename "$PWD" 2>/dev/null)
    local par; par=$(basename "$(dirname "$PWD")" 2>/dev/null)
    [ "$cur" = "/" ] || [ -z "$cur" ] && cur="root"
    [ "$cur" = "files" ] && cur="home"
    [ "$par" = "files" ] && par="home"
    if [ -n "$par" ] && [ "$par" != "/" ] && [ "$par" != "." ]; then
        echo "${par}/${cur}"
    else
        echo "$cur"
    fi
}

_ter_preexec_title() {
    if [ -n "$MANUAL_TAB_NAME" ]; then return; fi

    local cmd="$1"
    local cmd_name="${cmd%% *}"
    local cmd_arg="${cmd#* }"
    [ "$cmd_arg" = "$cmd" ] && cmd_arg=""

    # Pick a useful detail per command class. Always lead with cmd_name
    # so a narrow side panel truncating from the right still shows it.
    local detail
    case "$cmd_name" in
        ssh|scp|mosh|ping|adb)
            detail="${cmd_arg%% *}"
            ;;
        vim|nvim|nano|cat|less|bat|tail|head|code)
            detail=$(basename "${cmd_arg%% *}" 2>/dev/null)
            ;;
        *)
            detail=$(_ter_short_pwd)
            ;;
    esac
    [ -z "$detail" ] && detail=$(_ter_short_pwd)

    local prefix=""
    [ -n "$NEXUS_SERVICE_NAME" ] && prefix="$NEXUS_SERVICE_NAME:"

    # For long-running agent sessions, append a 3-digit shell PID suffix
    # so multiple Claude/agy sessions are distinguishable in the side panel.
    local suffix=""
    case "$cmd_name" in
        claude|agy|ai|aichat|aider)
            suffix=" #$(printf '%03d' "$(( $$ % 1000 ))")"
            ;;
    esac

    _ter_set_title "${prefix}${cmd_name}: ${detail}${suffix}"
}

if [ -n "$ZSH_VERSION" ]; then
    autoload -Uz add-zsh-hook 2>/dev/null
    add-zsh-hook precmd _ter_precmd_title 2>/dev/null
    add-zsh-hook preexec _ter_preexec_title 2>/dev/null
else
    # Bash fallback
    PROMPT_COMMAND="_ter_precmd_title; $PROMPT_COMMAND"
fi
