#!/data/data/com.termux/files/usr/bin/bash
# ── TER: OpenCode CLI Launcher for Termux ──
# Keep TER's tab-title logic in charge: stop opencode from overriding the
# terminal/session name with "OC | <session>".
export OPENCODE_DISABLE_TERMINAL_TITLE=1

oc_bin="${OPENCODE_BIN:-$HOME/.opencode/bin/opencode}"
if [ ! -f "$oc_bin" ]; then
    if [ -f "$HOME/.local/share/opencode/bin/opencode" ]; then
        oc_bin="$HOME/.local/share/opencode/bin/opencode"
    fi
fi

if [ ! -f "$oc_bin" ]; then
    echo "opencode: binary not found ($oc_bin)." >&2
    exit 1
fi

if [ -n "${PREFIX:-}" ] && command -v glibc-runner >/dev/null 2>&1; then
    exec glibc-runner "$oc_bin" "$@"
elif [ -n "${PREFIX:-}" ] && [ -x "$PREFIX/glibc/bin/ld.so" ]; then
    unset LD_PRELOAD
    exec "$PREFIX/glibc/bin/ld.so" "$oc_bin" "$@"
elif [ -n "${PREFIX:-}" ]; then
    echo "opencode: glibc-runner is required to run Linux glibc binaries in Termux." >&2
    echo "  Install it with: pkg install glibc-runner" >&2
    exit 127
else
    exec "$oc_bin" "$@"
fi
