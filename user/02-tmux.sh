# ── Auto-Start Tmux ──
# Automatically launches the tabbed tmux interface on startup
# if we aren't already inside a tmux session.

if [ -z "$TMUX" ] && [ -n "$PS1" ]; then
    if tmux has-session -t main 2>/dev/null; then
        exec tmux attach-session -t main
    else
        exec tmux new-session -s main
    fi
fi
