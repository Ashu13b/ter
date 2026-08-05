# ── Codex CLI Network Launcher (Tinyproxy, Rust TLS & MCP Fix) ──
codext() {
    # Ensure tinyproxy is running on port 8888
    if ! pgrep -x tinyproxy >/dev/null 2>&1; then
        if [ -f "/data/data/com.termux/files/usr/etc/tinyproxy/tinyproxy.conf" ]; then
            tinyproxy -c /data/data/com.termux/files/usr/etc/tinyproxy/tinyproxy.conf >/dev/null 2>&1 || true
        fi
    fi

    if [ -f "$HOME/.local/bin/codex" ]; then
        # Rust & reqwest TLS certificate bundle paths for Termux (fixes MCP SSL handshake)
        export SSL_CERT_FILE="/data/data/com.termux/files/usr/etc/tls/cert.pem"
        export SSL_CERT_DIR="/data/data/com.termux/files/usr/etc/tls/certs"
        export NODE_EXTRA_CA_CERTS="/data/data/com.termux/files/usr/etc/tls/cert.pem"
        
        # Proxy settings (both upper and lowercase for Rust reqwest & Node)
        export HTTP_PROXY="http://127.0.0.1:8888"
        export HTTPS_PROXY="http://127.0.0.1:8888"
        export ALL_PROXY="http://127.0.0.1:8888"
        export http_proxy="http://127.0.0.1:8888"
        export https_proxy="http://127.0.0.1:8888"
        export all_proxy="http://127.0.0.1:8888"
        
        # DNS Resolution settings
        export RESOLV_NAMESERVERS="8.8.8.8"
        export GODEBUG="netdns=go"

        "$HOME/.local/bin/codex" "$@"
    else
        echo "codex binary not found in $HOME/.local/bin/codex"
        return 1
    fi
}
