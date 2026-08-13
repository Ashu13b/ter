# ── Shell Startup Execution ──
# Optionally runs the ADB-backed stability status on interactive startup.
# Disabled by default because device/network timeouts must never delay a prompt.
# Guarded so re-sourcing (.bashrc + .zshrc + tmux auto-start) doesn't
# print the status banner multiple times.

if [ -t 1 ] && [ -z "$TER_STATUS_PRINTED" ]; then
    export TER_STATUS_PRINTED=1
    type _ter_load_startup_config >/dev/null 2>&1 && _ter_load_startup_config
    if [ "$OPTIMIZE_STATUS" != "false" ]; then
        optimize status
    fi
    # Repository drift checks can traverse thousands of files and block a new
    # prompt for seconds. Keep them explicit via `ter doctor`.
fi
