# ── Shell Startup Execution ──
# Runs background stability status on interactive startup

if [ -t 1 ]; then
    optimize status
fi
