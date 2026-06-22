# ── Shell Startup Execution ──
# Runs background stability status on interactive startup.
# Guarded so re-sourcing (.bashrc + .zshrc + tmux auto-start) doesn't
# print the status banner multiple times.

if [ -t 1 ] && [ -z "$TER_STATUS_PRINTED" ]; then
    export TER_STATUS_PRINTED=1
    if [ -f "$HOME/.config/ter/startup.conf" ]; then
        source "$HOME/.config/ter/startup.conf"
    fi
    if [ "$OPTIMIZE_STATUS" != "false" ]; then
        optimize status
    fi
fi
