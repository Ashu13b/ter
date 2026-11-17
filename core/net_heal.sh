# ── TER: DNS resolver & Google API hosts healing ──
# Single source of truth. Sourced by the shell loader (core/, lexical order puts
# this after 01-config.sh), by install.sh and by extras/install-ai-agents.sh.
# bootstrap.sh keeps one inline resolver seed because it runs *before* the repo
# is cloned — nothing shared exists on disk at that point.
#
# The Google API entries written to $PREFIX/etc/hosts are pinned IPs. A pin that
# Google has since rotated breaks the domain outright (hosts always wins over
# DNS), so the block is rewritten once it is older than TER_NET_HEAL_TTL_DAYS and
# any domain that no longer resolves is dropped instead of being kept forever.
# `ter fix-dns` forces a refresh.

_TER_NET_HEAL_DOMAINS="oauth2.googleapis.com accounts.google.com cloudaicompanion.googleapis.com generativelanguage.googleapis.com cloudresourcemanager.googleapis.com iam.googleapis.com"
_TER_NET_HEAL_BEGIN="# >>> TER net-heal >>>"
_TER_NET_HEAL_END="# <<< TER net-heal <<<"

# True when a managed block exists and its stamp is younger than the TTL, so the
# common startup path never spends a DNS lookup.
_ter_net_heal_fresh() {
    local hosts="$1" ttl stamp now
    ttl="${TER_NET_HEAL_TTL_DAYS:-7}"
    case "$ttl" in ''|*[!0-9]*) ttl=7 ;; esac
    [ -f "$hosts" ] || return 1
    grep -Fq "$_TER_NET_HEAL_BEGIN" "$hosts" 2>/dev/null || return 1
    stamp=$(sed -n 's/^# TER net-heal stamp \([0-9][0-9]*\).*/\1/p' "$hosts" 2>/dev/null | head -n 1)
    case "${stamp:-}" in ''|*[!0-9]*) return 1 ;; esac
    now=$(date +%s 2>/dev/null) || return 1
    case "${now:-}" in ''|*[!0-9]*) return 1 ;; esac
    [ $((now - stamp)) -lt $((ttl * 86400)) ]
}

_ter_heal_dns() {
    local force="${1:-}"
    [ -n "${PREFIX:-}" ] && [ -d "$PREFIX/etc" ] || return 0
    local etc_dir="$PREFIX/etc"
    local hosts="$etc_dir/hosts"

    # Only seed a resolver when the system has none: never clobber provider DNS.
    if [ ! -s "$etc_dir/resolv.conf" ] || ! grep -q "^nameserver[[:space:]]" "$etc_dir/resolv.conf" 2>/dev/null; then
        cat << 'EOF' > "$etc_dir/resolv.conf" 2>/dev/null || true
nameserver 1.1.1.1
nameserver 8.8.8.8
nameserver 1.0.0.1
nameserver 8.8.4.4
options timeout:2 attempts:2
EOF
    fi

    # glibc-backed binaries (agy, opencode) read glibc/etc, not the Termux one.
    if [ -d "$PREFIX/glibc/etc" ]; then
        [ -e "$PREFIX/glibc/etc/resolv.conf" ] || ln -sf "$etc_dir/resolv.conf" "$PREFIX/glibc/etc/resolv.conf" 2>/dev/null || true
        [ -e "$PREFIX/glibc/etc/hosts" ] || ln -sf "$etc_dir/hosts" "$PREFIX/glibc/etc/hosts" 2>/dev/null || true
    fi

    if [ "$force" != "--force" ] && _ter_net_heal_fresh "$hosts"; then
        return 0
    fi
    command -v python3 >/dev/null 2>&1 || return 0

    python3 - "$hosts" "$_TER_NET_HEAL_BEGIN" "$_TER_NET_HEAL_END" "$_TER_NET_HEAL_DOMAINS" << 'PY' 2>/dev/null || true
import os
import socket
import sys
import time

hosts, begin, end, domains_arg = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
domains = domains_arg.split()

try:
    with open(hosts) as handle:
        original = handle.read()
except FileNotFoundError:
    original = "127.0.0.1 localhost\n::1 ip6-localhost\n"

kept, inside = [], False
for line in original.splitlines():
    stripped = line.strip()
    if stripped == begin:
        inside = True
        continue
    if stripped == end:
        inside = False
        continue
    if inside:
        continue
    # Header and bare pins written by earlier TER versions (no markers).
    if stripped.startswith("# Auto-resolved Google API hosts"):
        continue
    fields = stripped.split()
    if len(fields) == 2 and fields[1] in domains and fields[0].replace(".", "").isdigit():
        continue
    kept.append(line.rstrip())

pins = []
for domain in domains:
    try:
        pins.append("%s %s" % (socket.gethostbyname(domain), domain))
    except Exception:
        continue

# Offline or blocked: keep the working block rather than replacing it with
# nothing, and never stamp an empty one — that would suppress retries for the
# whole TTL. Legacy lines are still pruned, just without a block.
emit_block = True
if not pins:
    if begin in original:
        sys.exit(0)
    emit_block = False

while kept and not kept[-1]:
    kept.pop()
if emit_block:
    if kept:
        kept.append("")
    kept.append(begin)
    kept.append("# TER net-heal stamp %d — refreshed by ter fix-dns / install.sh" % int(time.time()))
    kept.extend(pins)
    kept.append(end)
updated = "\n".join(kept) + "\n" if kept else ""

if updated == original:
    sys.exit(0)

tmp = hosts + ".ter-heal.tmp"
with open(tmp, "w") as handle:
    handle.write(updated)
try:
    os.chmod(tmp, os.stat(hosts).st_mode)
except OSError:
    pass
os.replace(tmp, hosts)
PY
    return 0
}

_ter_heal_dns
