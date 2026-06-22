export TER_VERSION="1.2"
export TNL_REMOTE="ubu"; export TNL_DEF_FSERVER_PORT="6000"
export NET_CHECK_TARGET="8.8.8.8"; export NET_CHECK_PORT="80"

# Shell Identity
export MY_NAME="Ashish Yadav"
[ -n "$ZSH_VERSION" ] && export CURRENT_SHELL="zsh"
[ -n "$BASH_VERSION" ] && export CURRENT_SHELL="bash"

# Protected Ports
export TNL_PROTECTED_PORTS="22 8022 443"

# Secrets — load env vars from ~/.config/ter/secrets.env if present.
# Template lives at ~/ter/secrets.template (copy + fill, never commit values).
if [ -f "$HOME/.config/ter/secrets.env" ]; then
    set -a
    . "$HOME/.config/ter/secrets.env"
    set +a
fi
