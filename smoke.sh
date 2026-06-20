#!/usr/bin/env bash
# Smoke test: source all TER modules in bash and zsh, verify key commands exist.
# Run from anywhere: bash ~/ter/smoke.sh
set -u

REPO="$(cd "$(dirname "$0")" && pwd)"
EXPECT="re cls scan adbcon optimize tabname apps ter"
FAIL=0

run_in() {
    local shell="$1"
    local label="$2"
    if ! command -v "$shell" >/dev/null 2>&1; then
        echo "  [skip] $label not installed"
        return
    fi

    "$shell" --noprofile --norc 2>/dev/null -c '
        shopt -s expand_aliases 2>/dev/null
        for dir in core network user; do
            for f in '"$REPO"'/$dir/*.sh; do
                [ -f "$f" ] || continue
                # shellcheck disable=SC1090
                source "$f" 2>/dev/null || echo "SOURCE_FAIL:$f"
            done
        done
        for cmd in '"$EXPECT"'; do
            type "$cmd" >/dev/null 2>&1 || echo "MISSING:$cmd"
        done
    ' > ${TMPDIR:-/tmp}/ter-smoke.$$ 2>&1 || true

    if grep -q "^SOURCE_FAIL\|^MISSING" ${TMPDIR:-/tmp}/ter-smoke.$$; then
        echo "  [FAIL] $label:"
        sed 's/^/    /' ${TMPDIR:-/tmp}/ter-smoke.$$
        FAIL=$((FAIL+1))
    else
        echo "  [ ok ] $label"
    fi
    rm -f ${TMPDIR:-/tmp}/ter-smoke.$$
}

echo "TER smoke test — $REPO"
# zsh doesn't support --noprofile; use -f instead.
run_in bash "bash"
if command -v zsh >/dev/null 2>&1; then
    zsh -f -c '
        for dir in core network user; do
            for f in '"$REPO"'/$dir/*.sh; do
                [ -f "$f" ] || continue
                source "$f" 2>/dev/null || echo "SOURCE_FAIL:$f"
            done
        done
        for cmd in '"$EXPECT"'; do
            type "$cmd" >/dev/null 2>&1 || echo "MISSING:$cmd"
        done
    ' > ${TMPDIR:-/tmp}/ter-smoke.$$ 2>&1 || true
    if grep -q "^SOURCE_FAIL\|^MISSING" ${TMPDIR:-/tmp}/ter-smoke.$$; then
        echo "  [FAIL] zsh:"
        sed 's/^/    /' ${TMPDIR:-/tmp}/ter-smoke.$$
        FAIL=$((FAIL+1))
    else
        echo "  [ ok ] zsh"
    fi
    rm -f ${TMPDIR:-/tmp}/ter-smoke.$$
else
    echo "  [skip] zsh not installed"
fi

if [ "$FAIL" -eq 0 ]; then
    echo "✓ all checks passed"
    exit 0
else
    echo "✗ $FAIL shell(s) failed"
    exit 1
fi
