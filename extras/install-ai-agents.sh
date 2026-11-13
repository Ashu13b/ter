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

echo -e "\n\e[1;35m══ TER: Clean AI Agents Installer ══\e[0m\n"

# 1. Base Termux dependencies check
if command -v pkg >/dev/null 2>&1; then
    info "Verifying base packages (curl, ca-certificates, nodejs, tinyproxy, resolv-conf)..."
    local_pkgs=()
    for p in curl ca-certificates nodejs tinyproxy resolv-conf; do
        if ! dpkg -s "$p" >/dev/null 2>&1; then
            local_pkgs+=("$p")
        fi
    done
    if [ "${#local_pkgs[@]}" -gt 0 ]; then
        info "Installing missing dependencies: ${local_pkgs[*]}"
        DEBIAN_FRONTEND=noninteractive pkg install -y "${local_pkgs[@]}" >/dev/null 2>&1 || warn "Some packages could not be installed automatically."
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
            warn "agy is present but glibc loader is missing; re-running wallentx installer..."
            curl -fsSL https://raw.githubusercontent.com/wallentx/antigravity-cli-termux/dev/install.sh | bash || true
        fi
    else
        info "Installing agy (Termux standalone VA39 port by wallentx)..."
        if curl -fsSL https://raw.githubusercontent.com/wallentx/antigravity-cli-termux/dev/install.sh | bash; then
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
        info "Installing codex standalone binary..."
        if curl -fsSL https://chatgpt.com/codex/install.sh | sh 2>/dev/null; then
            success "codex installed via official script."
        elif command -v npm >/dev/null 2>&1; then
            info "Falling back to npm install -g @openai/codex..."
            npm install -g @openai/codex >/dev/null 2>&1 && success "codex installed via npm." || warn "Failed to install codex via npm."
        else
            warn "Could not install codex automatically."
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
        info "Installing opencode via official installer..."
        if curl -fsSL https://opencode.ai/v2/install | bash; then
            success "opencode installed successfully."
        else
            warn "Failed to install opencode automatically."
        fi
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
        if ! command -v npm >/dev/null 2>&1 && command -v pkg >/dev/null 2>&1; then
            pkg install -y nodejs >/dev/null 2>&1 || true
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
