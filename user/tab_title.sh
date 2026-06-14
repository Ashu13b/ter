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
        elif [ -n "$NEXUS_SERVICE_NAME" ]; then
            prefix="$NEXUS_SERVICE_NAME:"
        fi
        title="ter:${prefix}${folder}"
    fi

    if [ -n "$ZSH_VERSION" ]; then
        (
            for i in 1 2 3 4 5; do
                sleep 1
                printf "\e]0;%s\a" "${title}"
            done
        ) < /dev/null 2>/dev/null &!
    else
        (
            for i in 1 2 3 4 5; do
                sleep 1
                printf "\e]0;%s\a" "${title}"
            done
        ) < /dev/null 2>/dev/null &
        disown %+ 2>/dev/null || disown $! 2>/dev/null || true
    fi
    hash -r 2>/dev/null
}
