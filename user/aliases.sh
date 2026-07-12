# ── Listing ──
alias ls='ls --color=auto --group-directories-first'; alias ll='ls -lah'

# ── Navigation ──
cd() {
    if [ "$1" = "ws" ]; then
        builtin cd /storage/emulated/0/workspace
    elif [ "$1" = "dl" ]; then
        builtin cd /storage/emulated/0/Download
    else
        builtin cd "$@"
    fi
}
alias ..='cd ..'; alias ...='cd ../..'

# ── Package Management ──
alias up='pkg update && pkg upgrade -y'; alias re='[ -n "$ZSH_VERSION" ] && source ~/.zshrc || source ~/.bashrc'

# ── Utility ──
alias cls='clear'
alias path='echo -e ${PATH//:/\\n}'

# ── Network Utilities ──
get_lan_ip() {
    python3 -c "import socket; s=socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.connect(('8.8.8.8', 80)); print(s.getsockname()[0]); s.close()" 2>/dev/null || echo "127.0.0.1"
}

# ── Project Shortcuts ──
alias kocr-app='cd ~/kaggle-ocr'; alias kocr-res='cd ~/kaggle-ocr/results'
alias nx-portal='(sleep 1.5 && termux-open http://127.0.0.1:19080 >/dev/null 2>&1) & python3 ~/nexus/nexus.py portal'
alias nx-watch='python3 ~/nexus/nexus.py watch'

# ── Fix/Kill ──
alias kill-all-bg='pkill -u $(id -u)'; alias fix-termux='termux-reload-settings && reset'
# unstuck: clear leaked xterm mouse-tracking after a dead SSH/tailscale/vim
# session leaves Termux echoing `65;39;38M`-style garbage on every touch.
alias unstuck='printf "\e[?1000l\e[?1002l\e[?1003l\e[?1006l"'
