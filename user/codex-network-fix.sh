# ── Codex CLI Network Launcher (Tinyproxy, Rust TLS & MCP Fix) ──
_codext_proxy_ready() {
    local port="$1"
    command -v curl >/dev/null 2>&1 || return 1
    # Android restricts the netlink/process metadata used by `ss -p`. Query
    # Tinyproxy's built-in statistics host instead; an unrelated listener will
    # not return the expected Tinyproxy page.
    curl -fsS --max-time 1 --noproxy '' \
        --proxy "http://127.0.0.1:$port" http://tinyproxy.stats/ 2>/dev/null \
        | grep -Fqi 'tinyproxy'
}

# Run in a subshell so proxy and TLS overrides never leak into the caller.
codext() (
    local config="${CODEXT_TINYPROXY_CONFIG:-/data/data/com.termux/files/usr/etc/tinyproxy/tinyproxy.conf}"
    local codex_bin="${CODEXT_BIN:-$HOME/.local/bin/codex}"
    local port proxy_url no_proxy_value i

    if [ ! -x "$codex_bin" ]; then
        echo "codex executable not found at $codex_bin"
        return 1
    fi

    if ! command -v tinyproxy >/dev/null 2>&1; then
        echo "codext requires tinyproxy (run: pkg install tinyproxy)."
        return 127
    fi
    if ! command -v curl >/dev/null 2>&1; then
        echo "codext requires curl (run: pkg install curl)."
        return 127
    fi
    if [ ! -r "$config" ]; then
        echo "tinyproxy configuration is missing or unreadable: $config"
        return 1
    fi

    port=$(awk 'tolower($1) == "port" { print $2; exit }' "$config")
    if ! [[ "$port" =~ ^[0-9]{1,5}$ ]] || (( 10#$port < 1 || 10#$port > 65535 )); then
        echo "tinyproxy configuration has an invalid Port value: ${port:-missing}"
        return 1
    fi

    if ! _codext_proxy_ready "$port"; then
        # A concurrent codext invocation may win the startup race. Always wait
        # for the owned listener before deciding that startup failed.
        tinyproxy -c "$config" >/dev/null 2>&1 || true
        for i in 1 2 3 4 5 6 7 8 9 10; do
            _codext_proxy_ready "$port" && break
            sleep 0.1
        done
    fi
    if ! _codext_proxy_ready "$port"; then
        echo "tinyproxy did not become ready on 127.0.0.1:$port"
        return 1
    fi

    if [ -r "/data/data/com.termux/files/usr/etc/tls/cert.pem" ]; then
        export SSL_CERT_FILE="/data/data/com.termux/files/usr/etc/tls/cert.pem"
        export NODE_EXTRA_CA_CERTS="$SSL_CERT_FILE"
    fi
    if [ -d "/data/data/com.termux/files/usr/etc/tls/certs" ]; then
        export SSL_CERT_DIR="/data/data/com.termux/files/usr/etc/tls/certs"
    fi

    proxy_url="http://127.0.0.1:$port"
    export HTTP_PROXY="$proxy_url"
    export HTTPS_PROXY="$proxy_url"
    export http_proxy="$proxy_url"
    export https_proxy="$proxy_url"
    no_proxy_value="${NO_PROXY:+$NO_PROXY,}127.0.0.1,localhost,::1"
    export NO_PROXY="$no_proxy_value"
    export no_proxy="$no_proxy_value"

    "$codex_bin" "$@"
)
