# ── Auto-Start Tmux ──
# Automatically launches the tabbed tmux interface on startup
# if we aren't already inside a tmux session.

if [ -f "$HOME/.config/ter/startup.conf" ]; then
    source "$HOME/.config/ter/startup.conf"
fi

if [ "$TMUX_AUTOSTART" != "false" ]; then

if [ -z "$TMUX" ] && [ -n "$PS1" ]; then
    # Always start a new independent session instead of attaching to a mirrored one
    exec tmux new-session
fi
fi
