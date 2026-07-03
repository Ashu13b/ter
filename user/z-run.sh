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
    # Passive health probe — silent on clean state, one line per warning.
    # Every new terminal doubles as a health check. Disable via
    # DOCTOR_QUIET=false in ~/.config/ter/startup.conf.
    if [ "$DOCTOR_QUIET" != "false" ] && command -v ter >/dev/null 2>&1; then
        ter doctor --quiet 2>/dev/null
    fi
fi
