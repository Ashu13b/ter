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
    # Self-check: surface a silently broken deployment instead of failing quiet.
    # Cheap `type` lookups only — must never delay the prompt.
    if ! type ter >/dev/null 2>&1 || ! type apps >/dev/null 2>&1; then
        echo -e "\033[0;33m⚠ TER self-check: core commands missing — run 'bash ~/ter/install.sh'\033[0m" >&2
    fi
    # Repository drift checks can traverse thousands of files and block a new
    # prompt for seconds. Keep them explicit via `ter doctor`.
fi
