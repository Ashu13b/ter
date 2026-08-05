#!/bin/bash
# ── TER: Termux Environment Setup ──
set -euo pipefail

# Sanitize PATH: prioritize Termux system binaries to avoid broken wrappers (e.g. nexus/bin)
export PATH="/data/data/com.termux/files/usr/bin:$PATH"

info() { echo -e "\e[34m[INFO]\e[0m $*"; }
success() { echo -e "\e[32m[OK]\e[0m $*"; }

REPO_DIR=$(cd "$(dirname "$0")" && pwd)
TARGET="$HOME/.shell.d"

echo -e "\n\e[1;35m══ TER: Termux Environment Installer ══\e[0m\n"

# Install required packages (idempotent — pkg is a no-op if already present).
if [ -f "$REPO_DIR/packages.txt" ] && command -v pkg >/dev/null 2>&1; then
    # Strip comments and blank lines without allowing package names to glob.
    mapfile -t PKGS < <(sed -E 's/[[:space:]]*#.*$//' "$REPO_DIR/packages.txt" | awk 'NF { print $1 }')
    if [ "${#PKGS[@]}" -gt 0 ] && [ "${TER_SKIP_PKG:-0}" != "1" ]; then
        info "Ensuring packages: ${PKGS[*]}"
        pkg install -y "${PKGS[@]}" >/dev/null 2>&1 && success "Packages OK." || info "pkg install reported errors (continuing)."
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
mkdir -p "$HOME/.config/ter/backups"

# Create automated timestamped backup of current TER environment before changes
backup_dir="$HOME/.config/ter/backups/backup_$(date +%Y%m%d_%H%M%S)"
if [ -d "$TARGET" ] || [ -d "$HOME/.config/ter" ]; then
    mkdir -p "$backup_dir"
    [ ! -d "$TARGET" ] || cp -R "$TARGET" "$backup_dir/shell.d" 2>/dev/null || true
    [ ! -d "$HOME/.config/ter" ] || cp -R "$HOME/.config/ter" "$backup_dir/ter_config" 2>/dev/null || true
    # Keep only the 10 most recent backups
    ls -1dt "$HOME/.config/ter/backups"/backup_* 2>/dev/null | tail -n +11 | xargs rm -rf 2>/dev/null || true
    success "TER backup snapshot saved to $backup_dir"
fi

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
    # Stage first, then swap the directory. A failed copy never leaves a
    # partially deployed module tree; apps/ remains outside this managed set.
    [ ! -L "$dst" ] || { info "Skipping $dir (target is a symlink)"; continue; }
    stage=$(mktemp -d "$TARGET/.${dir}.stage.XXXXXX")
    backup="$TARGET/.${dir}.backup.$$"
    if ! cp -R "$src"/. "$stage"/; then
        rm -rf "$stage"
        info "Failed to stage $dir; keeping deployed copy."
        continue
    fi
    # Preserve custom/untracked files from existing deployment (excluding bytecode cache)
    if [ -d "$dst" ]; then
        (
            cd "$dst"
            find . -type f ! -name "*.pyc" ! -path "*/__pycache__/*" | while read -r relfile; do
                relfile="${relfile#./}"
                if [ ! -f "$stage/$relfile" ]; then
                    mkdir -p "$(dirname "$stage/$relfile")"
                    cp -p "$relfile" "$stage/$relfile"
                fi
            done
        ) 2>/dev/null || true
    fi
    mv "$dst" "$backup"
    if mv "$stage" "$dst"; then
        rm -rf "$backup"
    else
        mv "$backup" "$dst"
        rm -rf "$stage"
        info "Failed to deploy $dir; restored previous copy."
    fi
done
success "Shell modules and docs deployed to $TARGET"

# Runtime modules use this to find the source checkout even when it was cloned
# somewhere other than ~/ter.
printf '%s\n' "$REPO_DIR" > "$TARGET/.ter-repo"

# TER's own manifest — read by welcome.sh to render the command surface.
if [ -f "$REPO_DIR/manifest.json" ]; then
    cp "$REPO_DIR/manifest.json" "$TARGET/manifest.json"
fi


if [ -f "$REPO_DIR/termux.properties" ]; then
    cp "$REPO_DIR/termux.properties" "$HOME/.termux/termux.properties"
    success "Keyboard layout deployed."
fi

if [ -f "$REPO_DIR/.tmux.conf" ]; then
    # Symlink so 'ter theme' only has one file to write and edits stay in sync.
    if [ -L "$HOME/.tmux.conf" ]; then
        current_tmux=$(readlink -f "$HOME/.tmux.conf" 2>/dev/null || true)
        if [ "$current_tmux" = "$REPO_DIR/.tmux.conf" ]; then
            success "Tmux config already linked to repo."
        else
            mv "$HOME/.tmux.conf" "$HOME/.tmux.conf.bak.$(date +%s)"
            ln -s "$REPO_DIR/.tmux.conf" "$HOME/.tmux.conf"
            success "Tmux config: backed up unrelated symlink, linked repo."
        fi
    elif [ -f "$HOME/.tmux.conf" ]; then
        mv "$HOME/.tmux.conf" "$HOME/.tmux.conf.bak.$(date +%s)"
        ln -s "$REPO_DIR/.tmux.conf" "$HOME/.tmux.conf"
        success "Tmux config: backed up old, symlinked → repo."
    else
        ln -s "$REPO_DIR/.tmux.conf" "$HOME/.tmux.conf"
        success "Tmux config symlinked → repo."
    fi
fi

if [ -f "$REPO_DIR/make_motd.py" ] && [ "${TER_SKIP_MOTD:-0}" != "1" ]; then
    (cd "$REPO_DIR" && python3 make_motd.py >/dev/null 2>&1) && success "MOTD regenerated."
fi
if [ -f "$REPO_DIR/motd" ] && [ "${TER_SKIP_MOTD:-0}" != "1" ]; then
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
    if [ -r "$HOME/.shell.d/.ter-repo" ]; then
        IFS= read -r TER_REPO_DIR < "$HOME/.shell.d/.ter-repo"
        export TER_REPO_DIR
    fi
    for dir in core network user; do
        if [ -d "$HOME/.shell.d/$dir" ]; then
            while IFS= read -r -d "" f; do
                source "$f"
            done < <(find "$HOME/.shell.d/$dir" -maxdepth 1 -type f -name "*.sh" -print0 | sort -z)
        fi
    done
fi'

for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    # Fresh Termux may ship without an rc file; create one so the loader sticks.
    [ -f "$rc" ] || touch "$rc"
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

if [ "${TER_SKIP_RELOAD:-0}" != "1" ] && command -v termux-reload-settings &>/dev/null; then
    termux-reload-settings
fi

# Install pre-commit smoke hook (idempotent).
HOOK="$REPO_DIR/.git/hooks/pre-commit"
if [ "${TER_SKIP_HOOK:-0}" != "1" ] && [ -d "$REPO_DIR/.git" ] && { [ ! -e "$HOOK" ] || [ ! -s "$HOOK" ] || ! grep -q "smoke.sh" "$HOOK"; }; then
    cat > "$HOOK" << 'HOOK_EOF'
#!/data/data/com.termux/files/usr/bin/env bash
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
