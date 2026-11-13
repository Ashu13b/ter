# ── OpenCode CLI Termux Wrapper Module ──
# Handles glibc execution and terminal title preservation in Termux.

opencode() {
    # Keep TER's tab-title logic in charge: stop opencode from overriding the
    # terminal/session name with "OC | <session>".
    export OPENCODE_DISABLE_TERMINAL_TITLE=1

    local oc_bin="${OPENCODE_BIN:-$HOME/.opencode/bin/opencode}"
    if [ ! -f "$oc_bin" ]; then
        if [ -f "$HOME/.local/share/opencode/bin/opencode" ]; then
            oc_bin="$HOME/.local/share/opencode/bin/opencode"
        fi
    fi

    if [ ! -f "$oc_bin" ]; then
        # Search PATH for an external binary outside wrapper scripts
        local candidate
        candidate=$(whence -p opencode 2>/dev/null || which opencode 2>/dev/null || true)
        if [ -n "$candidate" ] && [ "$candidate" != "$HOME/.local/bin/opencode" ] && [ "$candidate" != "${PREFIX:-/data/data/com.termux/files/usr}/bin/opencode" ]; then
            oc_bin="$candidate"
        fi
    fi

    if [ ! -f "$oc_bin" ]; then
        echo "opencode: binary not found ($oc_bin)." >&2
        return 1
    fi

    # In Termux, glibc binaries require glibc-runner or ld.so to execute on Android Bionic
    if [ -n "${PREFIX:-}" ] && command -v glibc-runner >/dev/null 2>&1; then
        glibc-runner "$oc_bin" "$@"
    elif [ -n "${PREFIX:-}" ] && [ -x "$PREFIX/glibc/bin/ld.so" ]; then
        (
            unset LD_PRELOAD
            "$PREFIX/glibc/bin/ld.so" "$oc_bin" "$@"
        )
    elif [ -n "${PREFIX:-}" ]; then
        echo "opencode: glibc-runner is required to run Linux glibc binaries in Termux." >&2
        echo "  Install it with: pkg install glibc-runner" >&2
        return 127
    else
        "$oc_bin" "$@"
    fi
}
