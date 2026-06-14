#!/bin/bash
# ── TER: Termux Environment Setup ──
set -e

info() { echo -e "\e[34m[INFO]\e[0m $*"; }
success() { echo -e "\e[32m[OK]\e[0m $*"; }

REPO_DIR=$(cd "$(dirname "$0")" && pwd)
TARGET="$HOME/.shell.d"

echo -e "\n\e[1;35m══ TER: Termux Environment Installer ══\e[0m\n"

info "Creating directory layout..."
mkdir -p "$TARGET"/{core,network,user,apps,docs}
mkdir -p "$HOME/.termux"
mkdir -p "$HOME/.local/bin"

info "Deploying shell modules..."
for dir in core network user docs; do
    if [ -d "$REPO_DIR/$dir" ]; then
        cp -r "$REPO_DIR/$dir/"* "$TARGET/$dir/" 2>/dev/null || true
    fi
done
success "Shell modules and docs deployed to $TARGET"


if [ -f "$REPO_DIR/termux.properties" ]; then
    cp "$REPO_DIR/termux.properties" "$HOME/.termux/termux.properties"
    success "Keyboard layout deployed."
fi

if [ -f "$REPO_DIR/motd" ]; then
    MOTD_TARGET="/data/data/com.termux/files/usr/etc/motd"
    if [ -w "$MOTD_TARGET" ]; then
        cp "$REPO_DIR/motd" "$MOTD_TARGET"
        success "System MOTD updated."
    fi
fi

LOADER_MARKER="SHELL.D Modular Loader"
if ! grep -q "$LOADER_MARKER" "$HOME/.bashrc" 2>/dev/null; then
    info "Adding module loader to .bashrc..."
    cat >> "$HOME/.bashrc" << 'LOADER'

# ── SHELL.D Modular Loader ──
export PATH="$HOME/.local/bin:$PATH"
for dir in core network user; do
    if [ -d "$HOME/.shell.d/$dir" ]; then
        for f in $(find "$HOME/.shell.d/$dir" -maxdepth 1 -name "*.sh" | sort); do
            source "$f"
        done
    fi
done
LOADER
    success "Loader added to .bashrc"
else
    info "Loader already present in .bashrc"
fi

command -v termux-reload-settings &>/dev/null && termux-reload-settings

manual_path="$HOME/.shell.d/docs/cli_manual.md"
clickable_manual=$(echo -e "\e]8;;file://$manual_path\e\\\\$manual_path\e]8;;\e\\\\")

echo -e "\n\e[1;32m✔ TER environment installed successfully!\e[0m"
echo -e "📖 Read the local CLI manual: $clickable_manual"
echo -e "Run: source ~/.bashrc (or open a new terminal)\n"
