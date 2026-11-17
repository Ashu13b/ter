#!/usr/bin/env bash
# ── TER: Clean AI Agents & Compatibility Installer ──
# Installs agy, codex, opencode, and claude along with Termux runtime bridges.
# Clean installation: NO accounts, tokens, or personal info are copied.
set -euo pipefail

info()    { echo -e "\e[34m[INFO]\e[0m $*"; }
success() { echo -e "\e[32m[OK]\e[0m   $*"; }
warn()    { echo -e "\e[33m[WARN]\e[0m $*"; }

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
TEMPLATES_DIR="$SCRIPT_DIR/templates"
TARGET_AGENT="${1:-all}"

# ── Pinned third-party installs ──
# Nothing is piped into a shell: each installer is downloaded to a temp file and
# only then executed, so a truncated or tampered download can never half-run.
# Versions are pinned deliberately — bump them here instead of tracking `latest`,
# so an upstream break (or a hijacked release) needs a reviewed commit to land.
# Override per run with TER_AGY_VERSION / TER_CODEX_VERSION / TER_OPENCODE_VERSION;
# set the *_SHA256 variables to additionally require an exact checksum.
TER_AGY_VERSION="${TER_AGY_VERSION:-v1.5.5}"
TER_CODEX_VERSION="${TER_CODEX_VERSION:-0.169.0}"
TER_OPENCODE_VERSION="${TER_OPENCODE_VERSION:-2.2.6}"

make_workdir() {
    mktemp -d "${TMPDIR:-/tmp}/ter-agents.XXXXXX" 2>/dev/null || mktemp -d
}

# fetch_pinned <url> <dest> [sha256]
fetch_pinned() {
    local url="$1" dest="$2" want="${3:-}" got
    curl -fsSL --retry 2 --connect-timeout 20 -o "$dest" "$url" || return 1
    if [ ! -s "$dest" ]; then
        rm -f "$dest"
        return 1
    fi
    if [ -n "$want" ]; then
        got=$(sha256sum "$dest" 2>/dev/null | cut -d' ' -f1)
        if [ "$got" != "$want" ]; then
            warn "Checksum mismatch for $url (expected $want, got ${got:-none})."
            rm -f "$dest"
            return 1
        fi
    fi
}

# run_script <file> [args...] — refuse anything that is not a shell script.
run_script() {
    local script="$1"
    shift
    if [ "$(head -c 2 "$script" 2>/dev/null)" != "#!" ]; then
        warn "Refusing to execute $script: not a shell script."
        return 1
    fi
    bash "$script" "$@"
}

# Install agy from the pinned wallentx release, preferring the versioned archive
# over the installer's own "latest" lookup.
_agy_install_pinned() {
    local base="https://github.com/wallentx/antigravity-cli-termux"
    local work installer archive rc
    work=$(make_workdir) || { warn "Could not create a temp dir for the agy installer."; return 1; }
    installer="$work/agy-install.sh"
    archive="$work/antigravity-termux-standalone.tar.gz"
    if ! fetch_pinned "$base/raw/${TER_AGY_VERSION}/install.sh" "$installer" "${TER_AGY_INSTALL_SHA256:-}"; then
        warn "Could not fetch the pinned agy installer (${TER_AGY_VERSION})."
        rm -rf "$work"
        return 1
    fi
    if grep -q 'AGY_INSTALL_URL' "$installer" 2>/dev/null \
        && fetch_pinned "$base/releases/download/${TER_AGY_VERSION}/antigravity-termux-standalone.tar.gz" "$archive" "${TER_AGY_ARCHIVE_SHA256:-}"; then
        if ( export AGY_INSTALL_URL="file://$archive"; run_script "$installer" ); then rc=0; else rc=1; fi
    else
        warn "Pinned agy archive unavailable; using the ${TER_AGY_VERSION} installer's own download."
        if run_script "$installer"; then rc=0; else rc=1; fi
    fi
    rm -rf "$work"
    return "$rc"
}

echo -e "\n\e[1;35m══ TER: Clean AI Agents Installer ══\e[0m\n"

# 0. Ensure reliable DNS in Termux before any network downloads. Healing is
# shared with the shell modules and install.sh — one implementation only.
if [ -f "$SCRIPT_DIR/../core/net_heal.sh" ]; then
    . "$SCRIPT_DIR/../core/net_heal.sh"
fi

# 1. Base Termux dependencies check
if command -v pkg >/dev/null 2>&1; then
    info "Verifying base packages (curl, ca-certificates, libc++, nodejs, tinyproxy, resolv-conf, glibc-repo)..."
    local_pkgs=()
    for p in curl ca-certificates libc++ nodejs tinyproxy resolv-conf glibc-repo; do
        if ! dpkg -s "$p" >/dev/null 2>&1; then
            local_pkgs+=("$p")
        fi
    done
    if [ "${#local_pkgs[@]}" -gt 0 ]; then
        info "Installing missing dependencies: ${local_pkgs[*]}"
        DEBIAN_FRONTEND=noninteractive pkg install -y "${local_pkgs[@]}" >/dev/null 2>&1 || warn "Some packages could not be installed automatically."
    fi

    # Ensure Termux glibc packages are installed (provides ld-linux-aarch64.so.1)
    if [ -n "${PREFIX:-}" ] && [ ! -f "$PREFIX/glibc/lib/ld-linux-aarch64.so.1" ]; then
        info "Installing glibc and glibc-runner for native AI agents..."
        DEBIAN_FRONTEND=noninteractive pkg install -y glibc glibc-runner >/dev/null 2>&1 || warn "glibc install returned a warning."
    fi
fi

# ── 1. Antigravity CLI (agy) ──
install_agy() {
    info "Checking Antigravity CLI (agy)..."

    # Ensure Termux glibc loader exists (required by agy.va39)
    if [ -n "${PREFIX:-}" ] && command -v pkg >/dev/null 2>&1; then
        local glibc_loader="${PREFIX}/glibc/lib/ld-linux-aarch64.so.1"
        if [ ! -f "$glibc_loader" ]; then
            info "Installing glibc-repo and glibc (required by agy standalone port)..."
            DEBIAN_FRONTEND=noninteractive pkg install -y glibc-repo resolv-conf >/dev/null 2>&1 || true
            DEBIAN_FRONTEND=noninteractive pkg install -y glibc glibc-runner >/dev/null 2>&1 || warn "glibc package install had warnings."
        fi
    fi

    if command -v agy >/dev/null 2>&1; then
        local glibc_loader="${PREFIX:-/data/data/com.termux/files/usr}/glibc/lib/ld-linux-aarch64.so.1"
        if [ -f "$glibc_loader" ]; then
            success "agy already installed and glibc loader ready: $(command -v agy)"
        else
            warn "agy is present but glibc loader is missing; re-running pinned wallentx installer..."
            _agy_install_pinned || true
        fi
    else
        info "Installing agy ${TER_AGY_VERSION} (Termux standalone VA39 port by wallentx)..."
        if _agy_install_pinned; then
            success "agy installed successfully."
        else
            warn "Failed to install agy automatically via wallentx installer."
        fi
    fi

    # Seed clean default keybindings and settings if not present (NO tokens or private paths)
    local gemini_dir="$HOME/.gemini/antigravity-cli"
    mkdir -p "$gemini_dir"
    if [ ! -f "$gemini_dir/keybindings.json" ] && [ -f "$TEMPLATES_DIR/agy-keybindings.json" ]; then
        cp "$TEMPLATES_DIR/agy-keybindings.json" "$gemini_dir/keybindings.json"
        success "Seeded default agy keybindings template."
    fi
    if [ ! -f "$gemini_dir/settings.json" ] && [ -f "$TEMPLATES_DIR/agy-settings.json" ]; then
        cp "$TEMPLATES_DIR/agy-settings.json" "$gemini_dir/settings.json"
        success "Seeded default agy settings template (zero-token baseline)."
    fi
}

# ── 2. OpenAI Codex CLI (codex) ──
install_codex() {
    info "Checking OpenAI Codex CLI (codex)..."
    local codex_bin="${CODEXT_BIN:-$HOME/.local/bin/codex}"
    if [ -x "$codex_bin" ] || command -v codex >/dev/null 2>&1; then
        success "codex already installed."
    else
        # npm is the only route that accepts a version *and* verifies the
        # artifact itself (registry sha512), so the old `curl | sh` is gone.
        if command -v npm >/dev/null 2>&1; then
            info "Installing codex ${TER_CODEX_VERSION} via npm (version-pinned)..."
            if npm install -g "@openai/codex@${TER_CODEX_VERSION}" >/dev/null 2>&1; then
                success "codex ${TER_CODEX_VERSION} installed via npm."
            else
                warn "Failed to install codex ${TER_CODEX_VERSION} via npm."
            fi
        else
            warn "npm is required to install the pinned codex build but was not found."
        fi
    fi

    # Seed clean config.toml with title guard if not present
    local codex_dir="$HOME/.codex"
    mkdir -p "$codex_dir"
    if [ ! -f "$codex_dir/config.toml" ] && [ -f "$TEMPLATES_DIR/codex-config.toml" ]; then
        cp "$TEMPLATES_DIR/codex-config.toml" "$codex_dir/config.toml"
        success "Seeded default codex config.toml (tab title guard enabled)."
    fi
}

# ── 3. OpenCode CLI (opencode) ──
install_opencode() {
    info "Checking OpenCode CLI (opencode)..."
    if [ -n "${PREFIX:-}" ] && command -v pkg >/dev/null 2>&1; then
        if ! command -v glibc-runner >/dev/null 2>&1; then
            info "Enabling glibc-repo and installing glibc-runner for opencode..."
            pkg install -y glibc-repo >/dev/null 2>&1 || true
            pkg install -y glibc-runner >/dev/null 2>&1 || warn "glibc-runner install returned a warning."
        fi
    fi

    if [ -f "$HOME/.opencode/bin/opencode" ] || command -v opencode >/dev/null 2>&1; then
        success "opencode binary already present."
    else
        local work installer
        info "Installing opencode ${TER_OPENCODE_VERSION} (version-pinned)..."
        work=$(make_workdir) || { warn "Could not create a temp dir for the opencode installer."; return; }
        installer="$work/opencode-install.sh"
        # The release-tagged script is immutable; the redirect URL stays as a
        # fallback, and either way the shell is asked for the pinned version.
        if ! fetch_pinned "https://raw.githubusercontent.com/anomalyco/opencode/v${TER_OPENCODE_VERSION}/install" "$installer" "${TER_OPENCODE_INSTALL_SHA256:-}" \
            && ! fetch_pinned "https://opencode.ai/v2/install" "$installer" "${TER_OPENCODE_INSTALL_SHA256:-}"; then
            warn "Could not fetch the opencode installer."
        elif run_script "$installer" --version "$TER_OPENCODE_VERSION"; then
            success "opencode ${TER_OPENCODE_VERSION} installed successfully."
        else
            warn "Failed to install opencode ${TER_OPENCODE_VERSION} automatically."
        fi
        rm -rf "$work"
    fi

    # Deploy TER's wrapper to ~/.local/bin/opencode if runner script exists
    if [ -f "$SCRIPT_DIR/opencode-runner.sh" ]; then
        mkdir -p "$HOME/.local/bin"
        cp "$SCRIPT_DIR/opencode-runner.sh" "$HOME/.local/bin/opencode"
        chmod +x "$HOME/.local/bin/opencode"
        if command -v termux-fix-shebang >/dev/null 2>&1; then
            termux-fix-shebang "$HOME/.local/bin/opencode" >/dev/null 2>&1 || true
        fi
        success "Deployed opencode glibc wrapper to ~/.local/bin/opencode"
    fi
}

# ── 4. Claude Code CLI (claude) ──
install_claude() {
    info "Checking Claude Code CLI (claude)..."
    if command -v claude >/dev/null 2>&1; then
        success "claude already installed: $(command -v claude)"
    else
        if command -v pkg >/dev/null 2>&1; then
            # Ensure libc++ is up to date so node doesn't fail with missing C++ symbols
            if ! node -v >/dev/null 2>&1; then
                info "Updating nodejs & libc++ runtime..."
                DEBIAN_FRONTEND=noninteractive pkg install -y libc++ nodejs >/dev/null 2>&1 || true
            fi
        fi
        if command -v npm >/dev/null 2>&1; then
            info "Running: npm install -g @anthropic-ai/claude-code..."
            npm install -g @anthropic-ai/claude-code && success "claude installed successfully." || warn "npm install of claude failed."
        else
            warn "npm is required to install claude but was not found."
        fi
    fi
}

case "$TARGET_AGENT" in
    agy)
        install_agy
        ;;
    codex)
        install_codex
        ;;
    opencode)
        install_opencode
        ;;
    claude)
        install_claude
        ;;
    all|--all)
        install_agy
        install_codex
        install_opencode
        install_claude
        ;;
    *)
        echo "Usage: $0 [all|agy|codex|opencode|claude]" >&2
        exit 1
        ;;
esac

echo ""
success "AI agent installation step complete."
echo -e "💡 To verify all agents, run: \033[1;36mter diagnose ai\033[0m\n"
