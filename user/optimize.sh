# ── Termux Background Task Manager Wrapper ──
optimize() {
    local script="$HOME/.shell.d/user/optimize.py"
    [ -f "$script" ] || script="${TER_REPO:-$HOME/ter}/user/optimize.py"
    python3 "$script" "$@"
}
