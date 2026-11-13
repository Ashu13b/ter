# ── Auto-Start Tmux ──
# Automatically launches the tabbed tmux interface on startup
# if we aren't already inside a tmux session and running interactively in a real TTY.

type _ter_load_startup_config >/dev/null 2>&1 && _ter_load_startup_config

if [ "${TMUX_AUTOSTART:-true}" != "false" ]; then
    # Must satisfy all safety guards before attempting to launch tmux:
    # 1. Not already inside tmux: [ -z "$TMUX" ]
    # 2. stdin is a real TTY: [ -t 0 ] (prevents "open terminal failed: not a terminal")
    # 3. stdout is a real TTY: [ -t 1 ]
    # 4. Interactive shell prompt set: [ -n "$PS1" ]
    # 5. Terminal type is valid: [ -n "$TERM" ] && [ "$TERM" != "dumb" ]
    if [ -z "${TMUX:-}" ] && [ -t 0 ] && [ -t 1 ] && [ -n "${PS1:-}" ] && [ -n "${TERM:-}" ] && [ "$TERM" != "dumb" ]; then
        if command -v tmux >/dev/null 2>&1; then
            # Clean up stale background server if socket is broken or unresponsive (common after pkg upgrades)
            if ! tmux ls >/dev/null 2>&1 && pgrep -x tmux >/dev/null 2>&1; then
                tmux kill-server 2>/dev/null || pkill -x tmux 2>/dev/null || true
            fi

            # Run tmux safely:
            # - If tmux runs and exits normally (e.g. exit inside tmux), exit the outer shell.
            # - If tmux fails to start, DO NOT kill the shell (never use raw exec).
            #   Fall back to standard shell prompt so the user is never locked out.
            if tmux new-session; then
                exit 0
            else
                echo -e "\033[1;33m⚠ tmux autostart failed (code $?). Falling back to native shell.\033[0m" >&2
                echo -e "\033[0;36m  Fix: run 'tmux kill-server' or disable with 'ter toggle tmux'\033[0m" >&2
            fi
        fi
    fi
fi

