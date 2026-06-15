#!/bin/bash

# ── Dynamic Session Tab Naming ──
# Renames the Termux session tab shown in the drawer/side-panel.
tabname() {
    if [ -n "$*" ]; then
        export MANUAL_TAB_NAME="$*"
    else
        export MANUAL_TAB_NAME=""
    fi

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

    if [ -n "$ZSH_VERSION" ]; then
        (
            sleep 0.5
            printf "\e]0;%s\a" "${title}"
        ) < /dev/null 2>/dev/null &!
    else
        (
            sleep 0.5
            printf "\e]0;%s\a" "${title}"
        ) < /dev/null 2>/dev/null &
        disown $! 2>/dev/null || true
    fi
    hash -r 2>/dev/null
}
