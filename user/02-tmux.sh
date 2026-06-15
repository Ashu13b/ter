# ── Auto-Start Tmux ──
# Automatically launches the tabbed tmux interface on startup
# if we aren't already inside a tmux session.

if [ -z "$TMUX" ] && [ -n "$PS1" ]; then
    # We are in an interactive shell, but NOT in tmux.
    # Connect to the 'main' session, or create it if it doesn't exist.
    exec tmux attach-session -t main 2>/dev/null || exec tmux new-session -s main
fi
