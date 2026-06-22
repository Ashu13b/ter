#!/bin/bash
# ── TER: Termux Environment Setup ──
set -e

info() { echo -e "\e[34m[INFO]\e[0m $*"; }
success() { echo -e "\e[32m[OK]\e[0m $*"; }

REPO_DIR=$(cd "$(dirname "$0")" && pwd)
TARGET="$HOME/.shell.d"

echo -e "\n\e[1;35m══ TER: Termux Environment Installer ══\e[0m\n"

# Install required packages (idempotent — pkg is a no-op if already present).
if [ -f "$REPO_DIR/packages.txt" ] && command -v pkg >/dev/null 2>&1; then
    PKGS=$(grep -vE '^\s*(#|$)' "$REPO_DIR/packages.txt" | tr '\n' ' ')
    if [ -n "$PKGS" ] && [ "${TER_SKIP_PKG:-0}" != "1" ]; then
        info "Ensuring packages: $PKGS"
        pkg install -y $PKGS >/dev/null 2>&1 && success "Packages OK." || info "pkg install reported errors (continuing)."
    fi
fi

# Storage permission (cd ws / cd dl depend on ~/storage existing).
if [ ! -d "$HOME/storage" ] && command -v termux-setup-storage >/dev/null 2>&1; then
    info "Requesting storage permission (accept the Android prompt)..."
    termux-setup-storage
fi

info "Creating directory layout..."
mkdir -p "$TARGET"/{core,network,user,apps,docs}
mkdir -p "$HOME/.termux"
mkdir -p "$HOME/.local/bin"

info "Deploying shell modules..."
for dir in core network user docs; do
    src="$REPO_DIR/$dir"
    dst="$TARGET/$dir"
    [ -d "$src" ] || continue
    # Safety: only operate on paths under TARGET.
    case "$dst" in
        "$TARGET"/*) ;;
        *) info "Skipping $dir (unsafe target: $dst)"; continue ;;
    esac
    # Clear only managed entries; never touch apps/ (third-party registrations).
    find "$dst" -mindepth 1 -maxdepth 1 ! -name 'apps' -exec rm -rf {} +
    cp -r "$src"/. "$dst"/ 2>/dev/null || true
done
success "Shell modules and docs deployed to $TARGET"


if [ -f "$REPO_DIR/termux.properties" ]; then
    cp "$REPO_DIR/termux.properties" "$HOME/.termux/termux.properties"
    success "Keyboard layout deployed."
fi

if [ -f "$REPO_DIR/.tmux.conf" ]; then
    # Symlink so 'ter theme' only has one file to write and edits stay in sync.
    if [ -L "$HOME/.tmux.conf" ]; then
        ln -sfn "$REPO_DIR/.tmux.conf" "$HOME/.tmux.conf"
        success "Tmux config symlinked → repo."
    elif [ -f "$HOME/.tmux.conf" ]; then
        mv "$HOME/.tmux.conf" "$HOME/.tmux.conf.bak.$(date +%s)"
        ln -s "$REPO_DIR/.tmux.conf" "$HOME/.tmux.conf"
        success "Tmux config: backed up old, symlinked → repo."
    else
        ln -s "$REPO_DIR/.tmux.conf" "$HOME/.tmux.conf"
        success "Tmux config symlinked → repo."
    fi
fi

if [ -f "$REPO_DIR/make_motd.py" ]; then
    (cd "$REPO_DIR" && python3 make_motd.py >/dev/null 2>&1) && success "MOTD regenerated."
fi
if [ -f "$REPO_DIR/motd" ]; then
    MOTD_TARGET="/data/data/com.termux/files/usr/etc/motd"
    if [ -w "$MOTD_TARGET" ]; then
        cp "$REPO_DIR/motd" "$MOTD_TARGET"
        success "System MOTD updated."
    fi
fi

LOADER_MARKER="SHELL.D Modular Loader"
LOADER_BLOCK='
# ── SHELL.D Modular Loader ──
if [ -z "$TER_LOADED" ]; then
    export TER_LOADED=1
    export PATH="$HOME/.local/bin:$PATH"
    for dir in core network user; do
        if [ -d "$HOME/.shell.d/$dir" ]; then
            for f in $(find "$HOME/.shell.d/$dir" -maxdepth 1 -name "*.sh" | sort); do
                source "$f"
            done
        fi
    done
fi'

for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    [ -f "$rc" ] || continue
    if grep -q "$LOADER_MARKER" "$rc" 2>/dev/null; then
        if grep -q "TER_LOADED" "$rc" 2>/dev/null; then
            info "Loader (guarded) already present in $(basename "$rc")"
        else
            info "Upgrading unguarded loader in $(basename "$rc")..."
            # Strip old loader block (from marker line to the closing 'done').
            python3 - "$rc" << 'PY'
import sys, re
path = sys.argv[1]
text = open(path).read()
pat = re.compile(r'\n?# ── SHELL\.D Modular Loader ──\n(?:export PATH=.*?\n)?for dir in core network user; do\n.*?\ndone\n?',
                 re.DOTALL)
# Strip ALL matching unguarded blocks; the guarded one (with TER_LOADED) won't match.
new = pat.sub('\n', text)
open(path, 'w').write(new)
PY
            printf '%s\n' "$LOADER_BLOCK" >> "$rc"
            success "Loader upgraded in $(basename "$rc")"
        fi
    else
        info "Adding module loader to $(basename "$rc")..."
        printf '%s\n' "$LOADER_BLOCK" >> "$rc"
        success "Loader added to $(basename "$rc")"
    fi
done

command -v termux-reload-settings &>/dev/null && termux-reload-settings

# Install pre-commit smoke hook (idempotent).
HOOK="$REPO_DIR/.git/hooks/pre-commit"
if [ -d "$REPO_DIR/.git" ] && [ ! -e "$HOOK" -o ! -s "$HOOK" ] || ! grep -q "smoke.sh" "$HOOK" 2>/dev/null; then
    cat > "$HOOK" << 'HOOK_EOF'
#!/usr/bin/env bash
# Auto-installed by ter/install.sh — runs shell smoke test before commit.
REPO="$(git rev-parse --show-toplevel)"
[ -x "$REPO/smoke.sh" ] || exit 0
"$REPO/smoke.sh" >/dev/null 2>&1 || {
    echo "✗ pre-commit: smoke.sh failed. Run 'bash smoke.sh' to see details."
    exit 1
}
HOOK_EOF
    chmod +x "$HOOK"
    success "Pre-commit smoke hook installed."
fi

manual_path="$HOME/.shell.d/docs/cli_manual.md"

echo -e "\n\e[1;32m✔ TER environment installed successfully!\e[0m"
echo -e "📖 Read the local CLI manual: $manual_path"
echo -e "Run: source ~/.bashrc (or open a new terminal)\n"
