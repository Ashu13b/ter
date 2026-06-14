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
alias h='cd ~'; alias ws='cd /storage/emulated/0/workspace'; alias dl='cd /storage/emulated/0/Download';
alias ..='cd ..'; alias ...='cd ../..'

# ── Package Management ──
alias up='pkg update && pkg upgrade -y'; alias re='[ -n "$ZSH_VERSION" ] && source ~/.zshrc || source ~/.bashrc'

# ── Utility ──
alias cls='clear'; alias c='clear && pwd && ls'
alias path='echo -e ${PATH//:/\\n}'

# ── Network Utilities ──
get_lan_ip() {
    python3 -c "import socket; s=socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.connect(('8.8.8.8', 80)); print(s.getsockname()[0]); s.close()" 2>/dev/null || echo "127.0.0.1"
}

# ── Project Shortcuts ──
alias kocr-app='cd ~/kaggle-ocr'; alias kocr-res='cd ~/kaggle-ocr/results'

# ── Fix/Kill ──
alias kill-all-bg='pkill -u $(id -u)'; alias fix-termux='termux-reload-settings && reset'
