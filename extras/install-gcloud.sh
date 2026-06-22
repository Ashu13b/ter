#!/usr/bin/env bash
# extras/install-gcloud.sh — install Google Cloud CLI via proot-distro debian.
# gcloud has no native Termux build, so we host it inside a Debian rootfs and
# expose a thin wrapper on the Termux side.

set -euo pipefail

if ! command -v proot-distro >/dev/null 2>&1; then
    echo "→ proot-distro missing, installing"
    pkg install -y proot-distro
fi

if ! proot-distro list --installed 2>/dev/null | grep -q '^debian'; then
    echo "→ installing Debian rootfs (one-time, ~200MB)"
    proot-distro install debian
fi

echo "→ installing google-cloud-cli inside debian"
proot-distro login debian -- bash -c '
    set -e
    apt-get update -y
    apt-get install -y curl gnupg apt-transport-https ca-certificates
    if ! command -v gcloud >/dev/null 2>&1; then
        echo "deb https://packages.cloud.google.com/apt cloud-sdk main" \
            > /etc/apt/sources.list.d/google-cloud-sdk.list
        curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
            | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg
        apt-get update -y
        apt-get install -y google-cloud-cli
    fi
    gcloud --version | head -1
'

wrapper="$PREFIX/bin/gcloud"
cat > "$wrapper" <<'EOF'
#!/usr/bin/env bash
exec proot-distro login debian -- gcloud "$@"
EOF
chmod +x "$wrapper"
echo "✓ wrapper installed: $wrapper"
echo "  Run: gcloud auth login"
