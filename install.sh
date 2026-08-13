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
        # Preserve user-edited Termux configuration during unattended runs.
        if DEBIAN_FRONTEND=noninteractive pkg install -y \
            -o Dpkg::Options::=--force-confold "${PKGS[@]}" >/dev/null 2>&1; then
            success "Packages OK."
        else
            echo "Required package installation failed; TER was not deployed." >&2
            exit 1
        fi
    fi
fi

# Storage permission (cd ws / cd dl depend on ~/storage existing).
if [ ! -d "$HOME/storage" ] && command -v termux-setup-storage >/dev/null 2>&1; then
    info "Requesting storage permission (accept the Android prompt)..."
    termux-setup-storage
fi

if [ -L "$TARGET" ]; then
    echo "Refusing to deploy through symlinked runtime root: $TARGET" >&2
    exit 1
fi

had_runtime=0
had_config=0
[ -d "$TARGET" ] && had_runtime=1
[ -d "$HOME/.config/ter" ] && had_config=1

info "Creating directory layout..."
mkdir -p "$TARGET"/{core,network,user,apps,docs}
mkdir -p "$HOME/.termux"
mkdir -p "$HOME/.local/bin"
CONFIG_DIR="$HOME/.config/ter"
BACKUP_ROOT="$CONFIG_DIR/backups"
INSTALL_LOCK="$CONFIG_DIR/install.lock"
mkdir -p "$BACKUP_ROOT"
backup_stage=""
inventory_stage=""
deploy_dirs=()
deploy_stages=()
deploy_backups=()
committed=0
install_committing=0
aux_stage=""
aux_paths=()
aux_states=()

# Prevent concurrent installs from interleaving directory swaps and backups.
if ! mkdir "$INSTALL_LOCK" 2>/dev/null; then
    lock_pid=$(cat "$INSTALL_LOCK/pid" 2>/dev/null || true)
    if [[ "$lock_pid" =~ ^[0-9]+$ ]] && kill -0 "$lock_pid" 2>/dev/null; then
        echo "Another TER install is running (pid $lock_pid)." >&2
        exit 1
    fi
    rm -f "$INSTALL_LOCK/pid"
    if ! rmdir "$INSTALL_LOCK" 2>/dev/null || ! mkdir "$INSTALL_LOCK"; then
        echo "Cannot acquire install lock: $INSTALL_LOCK" >&2
        exit 1
    fi
fi
printf '%s\n' "$$" > "$INSTALL_LOCK/pid"
cleanup_install_lock() {
    if [ -n "$backup_stage" ] && [ -d "$backup_stage" ]; then
        rm -rf "$backup_stage"
    fi
    if [ -n "$inventory_stage" ] && [ -f "$inventory_stage" ]; then
        rm -f "$inventory_stage"
    fi

    # Restore every directory already swapped if the install is interrupted.
    if [ "$install_committing" -eq 1 ]; then
        for ((cleanup_i=committed-1; cleanup_i>=0; cleanup_i--)); do
            cleanup_dir="${deploy_dirs[$cleanup_i]}"
            cleanup_dst="$TARGET/$cleanup_dir"
            cleanup_backup="${deploy_backups[$cleanup_i]}"
            cleanup_new="$TARGET/.$cleanup_dir.interrupted.$$"
            if [ -d "$cleanup_backup" ]; then
                if [ -e "$cleanup_dst" ] || [ -L "$cleanup_dst" ]; then
                    if mv "$cleanup_dst" "$cleanup_new" 2>/dev/null \
                        && mv "$cleanup_backup" "$cleanup_dst" 2>/dev/null; then
                        rm -rf "$cleanup_new"
                    fi
                else
                    mv "$cleanup_backup" "$cleanup_dst" 2>/dev/null || true
                fi
            fi
        done

        # Restore files outside the swapped module directories as part of the
        # same transaction (shell rc files, metadata, Termux/tmux config, etc.).
        for ((cleanup_i=${#aux_paths[@]}-1; cleanup_i>=0; cleanup_i--)); do
            cleanup_dst="${aux_paths[$cleanup_i]}"
            if [ "${aux_states[$cleanup_i]}" = "present" ]; then
                if rm -f -- "$cleanup_dst" 2>/dev/null \
                    && cp -a -- "$aux_stage/$cleanup_i" "$cleanup_dst" 2>/dev/null; then
                    :
                else
                    echo "Rollback failed for $cleanup_dst; restore it from $aux_stage." >&2
                fi
            elif ! rm -f -- "$cleanup_dst" 2>/dev/null; then
                echo "Rollback failed while removing new file $cleanup_dst." >&2
            fi
        done
    fi

    for cleanup_stage in "${deploy_stages[@]}"; do
        if [ -d "$cleanup_stage" ]; then
            rm -rf "$cleanup_stage"
        fi
    done
    if [ -n "$aux_stage" ] && [ -d "$aux_stage" ] && [ "$install_committing" -eq 0 ]; then
        rm -rf "$aux_stage"
    fi

    # Keep the lock until rollback and stage cleanup are fully complete.
    rm -f "$INSTALL_LOCK/pid"
    rmdir "$INSTALL_LOCK" 2>/dev/null || true
}
trap cleanup_install_lock EXIT

# Create automated timestamped backup of current TER environment before changes
if [ "$had_runtime" -eq 1 ] || [ "$had_config" -eq 1 ]; then
    backup_stamp=$(date +%Y%m%d_%H%M%S)
    backup_stage=$(mktemp -d "$BACKUP_ROOT/.stage_$backup_stamp.XXXXXX")
    mkdir -p "$backup_stage/shell.d" "$backup_stage/ter_config"
    backup_failed=0

    if [ "$had_runtime" -eq 1 ] && ! cp -Rp "$TARGET"/. "$backup_stage/shell.d"/; then
        backup_failed=1
    fi
    if [ "$had_config" -eq 1 ]; then
        for entry in "$CONFIG_DIR"/* "$CONFIG_DIR"/.[!.]* "$CONFIG_DIR"/..?*; do
            [ -e "$entry" ] || [ -L "$entry" ] || continue
            entry_name=${entry##*/}
            case "$entry_name" in
                backups|install.lock) continue ;;
            esac
            cp -Rp -- "$entry" "$backup_stage/ter_config/" || backup_failed=1
        done
    fi
    if [ "$backup_failed" -ne 0 ]; then
        rm -rf "$backup_stage"
        echo "TER backup failed; deployment was not started." >&2
        exit 1
    fi

    backup_suffix=${backup_stage##*.}
    backup_dir="$BACKUP_ROOT/backup_${backup_stamp}_$backup_suffix"
    mv "$backup_stage" "$backup_dir"
    backup_stage=""

    success "TER backup snapshot saved to $backup_dir"
fi

# Snapshot every file mutated outside the managed module directories. These
# copies remain until the entire install succeeds and are restored on failure.
aux_stage=$(mktemp -d "$CONFIG_DIR/.install-rollback.XXXXXX")
snapshot_aux_file() {
    local path="$1" index=${#aux_paths[@]}
    aux_paths+=("$path")
    if [ -e "$path" ] || [ -L "$path" ]; then
        cp -a -- "$path" "$aux_stage/$index" || {
            echo "Cannot stage rollback copy for $path" >&2
            exit 1
        }
        aux_states+=("present")
    else
        aux_states+=("missing")
    fi
}
snapshot_aux_file "$TARGET/.ter-repo"
snapshot_aux_file "$TARGET/manifest.json"
snapshot_aux_file "$HOME/.termux/termux.properties"
snapshot_aux_file "$HOME/.tmux.conf"
snapshot_aux_file "$HOME/.bashrc"
snapshot_aux_file "$HOME/.zshrc"
snapshot_aux_file "$REPO_DIR/motd"
if [ "${TER_SKIP_MOTD:-0}" != "1" ] && [ -e "/data/data/com.termux/files/usr/etc/motd" ]; then
    snapshot_aux_file "/data/data/com.termux/files/usr/etc/motd"
fi
if [ -d "$REPO_DIR/.git" ]; then
    snapshot_aux_file "$REPO_DIR/.git/hooks/pre-commit"
fi

managed_inventory="$TARGET/.ter-managed-files"
was_managed() {
    local rel="$1"
    if [ -f "$managed_inventory" ] && grep -Fzxq -- "$rel" "$managed_inventory"; then
        return 0
    fi
    # Without an inventory, ownership cannot be proven. Preserve the file for
    # one upgrade; the inventory written by this install governs later removal.
    return 1
}

info "Staging shell modules..."
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
    if [ -L "$dst" ]; then
        for old_stage in "${deploy_stages[@]}"; do
            rm -rf "$old_stage"
        done
        echo "Refusing to replace symlinked module directory: $dst" >&2
        exit 1
    fi
    stage=$(mktemp -d "$TARGET/.$dir.stage.XXXXXX")
    if ! cp -R "$src"/. "$stage"/; then
        rm -rf "$stage"
        for old_stage in "${deploy_stages[@]}"; do
            rm -rf "$old_stage"
        done
        echo "Failed to stage $dir; deployment was not started." >&2
        exit 1
    fi

    # Preserve only genuinely custom files. Files recorded as managed (or
    # previously tracked by Git) are intentionally removed when absent in src.
    if [ -d "$dst" ]; then
        if ! (
            cd "$dst"
            preserve_failed=0
            while IFS= read -r -d "" relfile; do
                relfile="${relfile#./}"
                managed_rel="$dir/$relfile"
                if [ ! -e "$stage/$relfile" ] && [ ! -L "$stage/$relfile" ] && ! was_managed "$managed_rel"; then
                    mkdir -p "$(dirname "$stage/$relfile")"
                    cp -Pp "$relfile" "$stage/$relfile" || preserve_failed=1
                fi
            done < <(find . \( -type f -o -type l \) ! -name "*.pyc" ! -path "*/__pycache__/*" -print0)
            [ "$preserve_failed" -eq 0 ]
        ); then
            rm -rf "$stage"
            for old_stage in "${deploy_stages[@]}"; do
                rm -rf "$old_stage"
            done
            echo "Failed to preserve custom files from $dir; deployment was not started." >&2
            exit 1
        fi
    fi

    deploy_dirs+=("$dir")
    deploy_stages+=("$stage")
done

# Build the new managed-file inventory before changing the live tree.
inventory_stage=$(mktemp "$TARGET/.ter-managed-files.stage.XXXXXX")
for dir in "${deploy_dirs[@]}"; do
    (
        cd "$REPO_DIR/$dir"
        while IFS= read -r -d "" relfile; do
            printf '%s\0' "$dir/${relfile#./}"
        done < <(find . \( -type f -o -type l \) -print0)
    )
done | sort -z > "$inventory_stage"

install_committing=1
for ((i=0; i<${#deploy_dirs[@]}; i++)); do
    dir="${deploy_dirs[$i]}"
    dst="$TARGET/$dir"
    stage="${deploy_stages[$i]}"
    backup="$TARGET/.$dir.rollback.$$"
    if ! mv "$dst" "$backup"; then
        deploy_error=1
    else
        deploy_backups+=("$backup")
        committed=$((committed+1))
        if mv "$stage" "$dst"; then
            deploy_error=0
        else
            if mv "$backup" "$dst"; then
                committed=$((committed-1))
                unset 'deploy_backups[committed]'
            else
                # Keep this backup registered so EXIT cleanup retries it.
                echo "Immediate restore failed for $dir; retrying during rollback." >&2
            fi
            deploy_error=1
        fi
    fi

    if [ "$deploy_error" -ne 0 ]; then
        for ((j=committed-1; j>=0; j--)); do
            rollback_dir="${deploy_dirs[$j]}"
            rollback_dst="$TARGET/$rollback_dir"
            rollback_new="$TARGET/.${rollback_dir}.failed.$$"
            if mv "$rollback_dst" "$rollback_new" && mv "${deploy_backups[$j]}" "$rollback_dst"; then
                rm -rf "$rollback_new"
            else
                echo "Rollback failed for $rollback_dir; restore from the latest TER backup." >&2
            fi
        done
        for ((j=i; j<${#deploy_stages[@]}; j++)); do
            [ ! -e "${deploy_stages[$j]}" ] || rm -rf "${deploy_stages[$j]}"
        done
        rm -f "$inventory_stage"
        echo "Deployment failed while swapping $dir; previous modules were restored." >&2
        exit 1
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

# The complete install succeeded. Publish the matching inventory only now, then
# discard rollback copies. Until this point, any error restores the old modules.
mv "$inventory_stage" "$managed_inventory"
inventory_stage=""
install_committing=0
for backup in "${deploy_backups[@]}"; do
    rm -rf "$backup"
done
rm -rf "$aux_stage"
aux_stage=""

# Prune only after every install step succeeds, so a failed attempt never
# consumes one of the four retained recovery points.
backup_dirs=()
mapfile -t backup_dirs < <(ls -1dt -- "$BACKUP_ROOT"/backup_* 2>/dev/null || true)
for ((i=4; i<${#backup_dirs[@]}; i++)); do
    rm -rf -- "${backup_dirs[$i]}"
done

manual_path="$HOME/.shell.d/docs/cli_manual.md"
echo -e "\n\e[1;32m✔ TER environment installed successfully!\e[0m"
echo -e "📖 Read the local CLI manual: $manual_path"
echo -e "Run: source ~/.bashrc (or open a new terminal)\n"
