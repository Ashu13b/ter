#!/usr/bin/env bash
# TER bootstrap — run on a fresh Termux to get a fully configured environment.
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/Ashu13b/ter/main/bootstrap.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/Ashu13b/ter/main/bootstrap.sh | bash -s -- --ai
set -e

REPO_URL="${TER_REPO_URL:-https://github.com/Ashu13b/ter.git}"
REPO_DIR="${TER_REPO_DIR:-$HOME/ter}"

info()    { echo -e "\e[34m[INFO]\e[0m  $*"; }
success() { echo -e "\e[32m[OK]\e[0m    $*"; }
warn()    { echo -e "\e[33m[WARN]\e[0m  $*"; }

echo -e "\n\e[1;35m══ TER Bootstrap ══\e[0m"
echo "Repo: $REPO_URL"
echo "Dest: $REPO_DIR"
echo ""

# 1. Verify we're inside Termux & ensure reliable DNS resolution.
if [ -z "${PREFIX:-}" ] || [ ! -d "/data/data/com.termux" ]; then
    warn "This doesn't look like Termux. Continuing anyway."
elif [ -d "$PREFIX/etc" ]; then
    # Auto-seed multi-provider DNS so Go/glibc/git network calls never time out
    if [ ! -s "$PREFIX/etc/resolv.conf" ] || ! grep -q "nameserver" "$PREFIX/etc/resolv.conf" 2>/dev/null; then
        cat << 'EOF' > "$PREFIX/etc/resolv.conf" 2>/dev/null || true
nameserver 1.1.1.1
nameserver 8.8.8.8
nameserver 1.0.0.1
nameserver 8.8.4.4
options timeout:2 attempts:2
EOF
    fi
fi

# 2. Refresh package index & ensure git (skip if git already present).
if command -v pkg >/dev/null 2>&1; then
    # Auto-repair any interrupted dpkg state from previous aborted attempts
    dpkg --configure -a >/dev/null 2>&1 || true
    if ! command -v git >/dev/null 2>&1; then
        info "Updating package index..."
        DEBIAN_FRONTEND=noninteractive pkg update -y >/dev/null 2>&1 || warn "pkg update had warnings."
        info "Installing git (needed to clone the repo)..."
        DEBIAN_FRONTEND=noninteractive pkg install -y git >/dev/null 2>&1 || { warn "git install failed; cannot continue."; exit 1; }
    fi
fi

# 3. Clone or update repo.
if [ -d "$REPO_DIR/.git" ]; then
    info "Repo already cloned. Pulling latest..."
    git -C "$REPO_DIR" pull --ff-only || warn "pull failed; using local checkout."
else
    info "Cloning $REPO_URL → $REPO_DIR"
    git clone "$REPO_URL" "$REPO_DIR"
fi

# 4. Hand off to the regular installer.
success "Handing off to install.sh"
bash "$REPO_DIR/install.sh" "$@"

# 5. Sanity check (optional).
RUN_SMOKE=0
for arg in "$@"; do
    case "$arg" in
        --smoke) RUN_SMOKE=1 ;;
    esac
done
if [ "$RUN_SMOKE" -eq 1 ] && [ -x "$REPO_DIR/smoke.sh" ]; then
    info "Running smoke test..."
    bash "$REPO_DIR/smoke.sh" || warn "smoke test failed — inspect the output above."
fi

echo ""
success "TER bootstrap complete."
echo -e "Next: open a new terminal, or run \e[1msource ~/.bashrc\e[0m"
