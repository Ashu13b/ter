# ── Shell Startup Execution ──
# Runs background stability status on interactive startup

if [ -t 1 ]; then
    if [ -f "$HOME/.config/ter/startup.conf" ]; then
        source "$HOME/.config/ter/startup.conf"
    fi
    if [ "$OPTIMIZE_STATUS" != "false" ]; then
        optimize status
    fi
fi
