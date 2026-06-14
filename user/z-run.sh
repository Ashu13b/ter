# ── Shell Startup Execution ──
# Runs background stability status on interactive startup

if [ -t 1 ]; then
    termux-bg status
fi
