#!/data/data/com.termux/files/usr/bin/env bash
# Smoke test: source all TER modules in bash and zsh, verify key commands exist.
# Run from anywhere: bash ~/ter/smoke.sh
set -u

REPO="$(cd "$(dirname "$0")" && pwd)"
EXPECT="re cls scan adbcon optimize tabname apps ter dvop adb-apk"
FAIL=0

fail() {
    echo "  [FAIL] $1"
    FAIL=$((FAIL+1))
}

check_syntax() {
    local f
    for f in "$REPO"/install.sh "$REPO"/bootstrap.sh "$REPO"/smoke.sh "$REPO"/core/*.sh "$REPO"/network/*.sh "$REPO"/user/*.sh; do
        bash -n "$f" || fail "bash syntax: ${f#$REPO/}"
    done
    for f in "$REPO"/make_motd.py "$REPO"/user/*.py; do
        python3 -m py_compile "$f" || fail "Python syntax: ${f#$REPO/}"
    done
}

check_isolated_install() {
    local test_home
    test_home=$(mktemp -d "${TMPDIR:-/tmp}/ter-install.XXXXXX") || { fail "could not create install test directory"; return; }
    mkdir -p "$test_home/storage"
    if HOME="$test_home" TER_SKIP_PKG=1 TER_SKIP_MOTD=1 TER_SKIP_RELOAD=1 TER_SKIP_HOOK=1 bash "$REPO/install.sh" >/dev/null 2>&1 \
        && [ "$(cat "$test_home/.shell.d/.ter-repo")" = "$REPO" ] \
        && [ -f "$test_home/.shell.d/core/00-style.sh" ] \
        && [ -f "$test_home/.bashrc" ]; then
        echo "  [ ok ] isolated install"
    else
        fail "isolated install"
    fi
    rm -rf "$test_home"
}

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
check_syntax
check_isolated_install
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
