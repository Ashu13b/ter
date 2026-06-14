# ── Shell Startup Execution ──
# Runs the welcome dashboard and background stability status on interactive startup

if [ -t 1 ]; then
    welcome
    termux-bg status
fi
