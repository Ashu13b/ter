#!/usr/bin/env bash
# extras/install-claude.sh — install Claude Code CLI on a fresh Termux.
# Idempotent: safe to re-run. Requires nodejs (installed by packages.txt).

set -euo pipefail

if ! command -v node >/dev/null 2>&1; then
    echo "→ nodejs missing, installing"
    pkg install -y nodejs
fi

if command -v claude >/dev/null 2>&1; then
    echo "✓ claude already on PATH: $(command -v claude)"
    claude --version 2>/dev/null || true
    exit 0
fi

echo "→ npm install -g @anthropic-ai/claude-code"
npm install -g @anthropic-ai/claude-code

if command -v claude >/dev/null 2>&1; then
    echo "✓ installed: $(command -v claude)"
    claude --version 2>/dev/null || true
else
    echo "✗ install finished but 'claude' not on PATH. Check npm prefix:"
    npm config get prefix
    exit 1
fi
