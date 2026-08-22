#!/data/data/com.termux/files/usr/bin/env bash
# Smoke test: source all TER modules in bash and zsh, verify key commands exist.
# Run from anywhere: bash ~/ter/smoke.sh
set -u

REPO="$(cd "$(dirname "$0")" && pwd)"
EXPECT="re cls scan adbcon optimize tabname apps ter dvop adb-apk codext"
FAIL=0
SMOKE_OUTPUT=$(mktemp "${TMPDIR:-/tmp}/ter-smoke.XXXXXX") || exit 1
trap 'rm -f "$SMOKE_OUTPUT"' EXIT

fail() {
    echo "  [FAIL] $1"
    FAIL=$((FAIL+1))
}

check_syntax() {
    local f
    for f in "$REPO"/install.sh "$REPO"/bootstrap.sh "$REPO"/smoke.sh "$REPO"/core/*.sh "$REPO"/network/*.sh "$REPO"/user/*.sh "$REPO"/extras/*.sh; do
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
    if ! HOME="$test_home" TER_SKIP_PKG=1 TER_SKIP_MOTD=1 TER_SKIP_RELOAD=1 TER_SKIP_HOOK=1 bash "$REPO/install.sh" >/dev/null 2>&1; then
        fail "isolated install"
        rm -rf "$test_home"
        return
    fi

    printf '%s\n' '# custom' > "$test_home/.shell.d/user/custom-local.sh"
    printf '%s\n' '# retired' > "$test_home/.shell.d/user/retired-module.sh"
    printf 'user/retired-module.sh\0' >> "$test_home/.shell.d/.ter-managed-files"
    printf '%s\n' 'important=true' > "$test_home/.config/ter/private.conf"

    if ! HOME="$test_home" TER_SKIP_PKG=1 TER_SKIP_MOTD=1 TER_SKIP_RELOAD=1 TER_SKIP_HOOK=1 bash "$REPO/install.sh" >/dev/null 2>&1; then
        fail "isolated upgrade"
        rm -rf "$test_home"
        return
    fi

    local nested_backup
    nested_backup=$(find "$test_home/.config/ter/backups" -path '*/ter_config/backups' -print -quit 2>/dev/null)
    if [ "$(cat "$test_home/.shell.d/.ter-repo")" = "$REPO" ] \
        && [ -f "$test_home/.shell.d/core/00-style.sh" ] \
        && [ -f "$test_home/.bashrc" ] \
        && grep -Fq 'if [ "${TER_LOADED_PID:-}" != "$$" ]; then' "$test_home/.bashrc" \
        && ! grep -Fq 'export TER_LOADED=1' "$test_home/.bashrc" \
        && [ -f "$test_home/.shell.d/.ter-managed-files" ] \
        && [ -f "$test_home/.shell.d/user/custom-local.sh" ] \
        && [ ! -e "$test_home/.shell.d/user/retired-module.sh" ] \
        && find "$test_home/.config/ter/backups" -type f -name private.conf -print -quit | grep -q . \
        && [ -z "$nested_backup" ]; then
        echo "  [ ok ] isolated install + upgrade"
    else
        fail "isolated install + upgrade invariants"
    fi

    local shell loader_rc=0
    for shell in bash zsh; do
        command -v "$shell" >/dev/null 2>&1 || continue
        if [ "$shell" = "bash" ]; then
            HOME="$test_home" TMUX=ter-smoke TER_LOADED=1 TER_LOADED_PID=1 \
                bash --noprofile --norc -c \
                'source "$HOME/.bashrc"; type ter >/dev/null && type apps >/dev/null && type codext >/dev/null' \
                || loader_rc=1
        else
            HOME="$test_home" TMUX=ter-smoke TER_LOADED=1 TER_LOADED_PID=1 \
                zsh -f -c \
                'source "$HOME/.zshrc"; type ter >/dev/null && type apps >/dev/null && type codext >/dev/null' \
                || loader_rc=1
        fi
    done
    if [ "$loader_rc" -eq 0 ]; then
        echo "  [ ok ] child-shell command loading"
    else
        fail "child-shell command loading"
    fi

    mkdir "$test_home/.config/ter/install.lock"
    printf '%s\n' "$$" > "$test_home/.config/ter/install.lock/pid"
    if HOME="$test_home" TER_SKIP_PKG=1 TER_SKIP_MOTD=1 TER_SKIP_RELOAD=1 TER_SKIP_HOOK=1 bash "$REPO/install.sh" >/dev/null 2>&1; then
        fail "concurrent install lock"
    else
        echo "  [ ok ] concurrent install lock"
    fi

    rm -f "$test_home/.config/ter/install.lock/pid"
    rmdir "$test_home/.config/ter/install.lock"
    printf '%s\n' '# rollback marker' >> "$test_home/.shell.d/core/00-style.sh"
    printf '%s\n' '/previous/repository' > "$test_home/.shell.d/.ter-repo"
    printf '%s\n' '{"previous":true}' > "$test_home/.shell.d/manifest.json"
    rm -f "$test_home/.termux/termux.properties"
    ln -s /dev/full "$test_home/.termux/termux.properties"
    if HOME="$test_home" TER_SKIP_PKG=1 TER_SKIP_MOTD=1 TER_SKIP_RELOAD=1 TER_SKIP_HOOK=1 \
        bash "$REPO/install.sh" >/dev/null 2>&1 \
        || ! grep -q '# rollback marker' "$test_home/.shell.d/core/00-style.sh" \
        || [ "$(cat "$test_home/.shell.d/.ter-repo")" != "/previous/repository" ] \
        || ! grep -q 'previous' "$test_home/.shell.d/manifest.json"; then
        fail "post-deploy failure rollback"
    else
        echo "  [ ok ] post-deploy failure rollback"
    fi

    printf '%s\n' '# ── SHELL.D Modular Loader ──' 'if [ -z "$TER_LOADED" ]; then' '    export PATH="$HOME/.local/bin:$PATH"' 'fi' > "$test_home/.zshrc"
    if HOME="$test_home" TER_SKIP_PKG=1 TER_SKIP_MOTD=1 TER_SKIP_RELOAD=1 TER_SKIP_HOOK=1 \
        bash "$REPO/install.sh" >/dev/null 2>&1 \
        || ! grep -Fq 'if [ -z "$TER_LOADED" ]; then' "$test_home/.zshrc" \
        || grep -Fq 'TER_LOADED_PID' "$test_home/.zshrc"; then
        fail "malformed loader guard rejection"
    else
        echo "  [ ok ] malformed loader guard rejection"
    fi
    rm -rf "$test_home"
}

check_package_failure() {
    local test_home
    test_home=$(mktemp -d "${TMPDIR:-/tmp}/ter-pkg-fail.XXXXXX") || { fail "could not create package test directory"; return; }
    mkdir -p "$test_home/storage"
    if TEST_HOME="$test_home" TEST_REPO="$REPO" bash --noprofile --norc -c '
        pkg() { return 1; }
        export -f pkg
        HOME="$TEST_HOME" TER_SKIP_MOTD=1 TER_SKIP_RELOAD=1 TER_SKIP_HOOK=1 bash "$TEST_REPO/install.sh" >/dev/null 2>&1
    '; then
        fail "required package failure propagation"
    else
        echo "  [ ok ] required package failure propagation"
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

    local rc=0
    "$shell" --noprofile --norc 2>/dev/null -c '
        smoke_failed=0
        shopt -s expand_aliases 2>/dev/null
        for dir in core network user; do
            for f in '"$REPO"'/$dir/*.sh; do
                [ -f "$f" ] || continue
                # shellcheck disable=SC1090
                source "$f" 2>/dev/null || { echo "SOURCE_FAIL:$f"; smoke_failed=1; }
            done
        done
        for cmd in '"$EXPECT"'; do
            type "$cmd" >/dev/null 2>&1 || { echo "MISSING:$cmd"; smoke_failed=1; }
        done
        [ "$smoke_failed" -eq 0 ] || exit 1
        echo SMOKE_COMPLETE
    ' > "$SMOKE_OUTPUT" 2>&1 || rc=$?

    if [ "$rc" -ne 0 ] || ! grep -q '^SMOKE_COMPLETE$' "$SMOKE_OUTPUT" \
        || grep -q "^SOURCE_FAIL\|^MISSING" "$SMOKE_OUTPUT"; then
        echo "  [FAIL] $label:"
        sed 's/^/    /' "$SMOKE_OUTPUT"
        FAIL=$((FAIL+1))
    else
        echo "  [ ok ] $label"
    fi
    : > "$SMOKE_OUTPUT"
}

check_adb_validation() {
    local adb_test_dir
    # shellcheck disable=SC1090
    source "$REPO/network/adb_connect.sh"
    if _adbcon_valid_ipv4 "192.168.1.10" \
        && ! _adbcon_valid_ipv4 "256.1.1.1" \
        && ! _adbcon_valid_ipv4 "1.2.3" \
        && _adbcon_valid_port "1" \
        && _adbcon_valid_port "65535" \
        && ! _adbcon_valid_port "0" \
        && ! _adbcon_valid_port "65536" \
        && _adbcon_valid_pair_code "123456" \
        && ! _adbcon_valid_pair_code "12345" \
        && ! _adbcon_valid_pair_code "12ab56" \
        && PATH=/nonexistent adbcon --help >/dev/null \
        && ! adbcon --unknown >/dev/null 2>&1; then
        echo "  [ ok ] adb input validation"
    else
        fail "adb input validation"
        return
    fi

    adb_test_dir=$(mktemp -d "${TMPDIR:-/tmp}/ter-adb-timeout.XXXXXX") || { fail "could not create adb timeout test directory"; return; }
    printf '%s\n' '#!/bin/sh' 'sleep 2' > "$adb_test_dir/adb"
    chmod +x "$adb_test_dir/adb"
    if PATH="$adb_test_dir:$PATH" ADBCON_TIMEOUT_SECONDS=1 _adbcon_timed devices >/dev/null 2>&1; then
        fail "adb timeout enforcement"
    else
        echo "  [ ok ] adb timeout enforcement"
    fi
    if _adbcon_pair_succeeded 0 "Successfully paired to 192.168.1.2:12345" \
        && ! _adbcon_pair_succeeded 0 "device is not paired" \
        && ! _adbcon_pair_succeeded 1 "Successfully paired"; then
        echo "  [ ok ] adb pairing result validation"
    else
        fail "adb pairing result validation"
    fi
    if (
        _adbcon_timed() { [ "$1" != "kill-server" ]; }
        adbcon disconnect >/dev/null 2>&1
    ); then
        fail "adb disconnect failure propagation"
    else
        echo "  [ ok ] adb disconnect failure propagation"
    fi
    rm -rf "$adb_test_dir"
}

check_sync_paths() {
    local test_home shell
    test_home=$(mktemp -d "${TMPDIR:-/tmp}/ter-sync.XXXXXX") || { fail "could not create sync test directory"; return; }
    mkdir -p "$test_home/.shell.d/user" "$test_home/repo/user"
    printf '%s\n' 'colon payload' > "$test_home/.shell.d/user/name:part.sh"
    printf '%s\n' 'unicode payload' > "$test_home/.shell.d/user/space ✓.sh"

    for shell in bash zsh; do
        command -v "$shell" >/dev/null 2>&1 || continue
        rm -f "$test_home/repo/user/name:part.sh" "$test_home/repo/user/space ✓.sh"
        if [ "$shell" = "bash" ]; then
            HOME="$test_home" TER_REPO_DIR="$test_home/repo" TER_SOURCE="$REPO" \
                bash --noprofile --norc -c 'source "$TER_SOURCE/user/ter_cmd.sh"; ter sync --yes >/dev/null'
        else
            HOME="$test_home" TER_REPO_DIR="$test_home/repo" TER_SOURCE="$REPO" \
                zsh -f -c 'source "$TER_SOURCE/user/ter_cmd.sh"; ter sync --yes >/dev/null'
        fi
        if [ "$(< "$test_home/repo/user/name:part.sh")" != "colon payload" ] \
            || [ "$(< "$test_home/repo/user/space ✓.sh")" != "unicode payload" ]; then
            fail "atomic sync paths ($shell)"
            rm -rf "$test_home"
            return
        fi
    done

    printf '%s\n' 'outside' > "$test_home/outside"
    rm -f "$test_home/repo/user/name:part.sh"
    ln -s "$test_home/outside" "$test_home/repo/user/name:part.sh"
    printf '%s\n' 'changed' > "$test_home/.shell.d/user/name:part.sh"
    if HOME="$test_home" TER_REPO_DIR="$test_home/repo" TER_SOURCE="$REPO" \
        bash --noprofile --norc -c 'source "$TER_SOURCE/user/ter_cmd.sh"; ter sync --yes >/dev/null 2>&1' \
        || [ "$(< "$test_home/outside")" != "outside" ]; then
        fail "sync symlink refusal"
        rm -rf "$test_home"
        return
    fi

    rm -f "$test_home/repo/user/name:part.sh"
    mv "$test_home/repo/user" "$test_home/repo/user.real"
    mkdir "$test_home/outside-dir"
    ln -s "$test_home/outside-dir" "$test_home/repo/user"
    if HOME="$test_home" TER_REPO_DIR="$test_home/repo" TER_SOURCE="$REPO" \
        bash --noprofile --norc -c 'source "$TER_SOURCE/user/ter_cmd.sh"; ter sync --yes >/dev/null 2>&1' \
        || [ -e "$test_home/outside-dir/name:part.sh" ]; then
        fail "sync parent symlink refusal"
        rm -rf "$test_home"
        return
    fi
    rm "$test_home/repo/user"
    mv "$test_home/repo/user.real" "$test_home/repo/user"

    mkdir "$test_home/.config/ter/sync.lock"
    printf '%s\n' "$$" > "$test_home/.config/ter/sync.lock/pid"
    if HOME="$test_home" TER_REPO_DIR="$test_home/repo" TER_SOURCE="$REPO" \
        bash --noprofile --norc -c 'source "$TER_SOURCE/user/ter_cmd.sh"; ter sync --yes >/dev/null 2>&1'; then
        fail "concurrent sync lock"
        rm -rf "$test_home"
        return
    fi

    echo "  [ ok ] atomic sync paths"
    rm -rf "$test_home"
}

check_codext_scope() {
    local test_home
    # shellcheck disable=SC1090
    source "$REPO/user/codex-network-fix.sh"
    test_home=$(mktemp -d "${TMPDIR:-/tmp}/ter-codext.XXXXXX") || { fail "could not create codext test directory"; return; }
    printf '%s\n' 'Port 8888' > "$test_home/tinyproxy.conf"
    printf '%s\n' '#!/bin/sh' 'exit 0' > "$test_home/codex"
    chmod +x "$test_home/codex"

    if (
        curl() { printf '%s\n' '<title>Stats [tinyproxy]</title>'; }
        _codext_proxy_ready 8888
    ) && ! (
        curl() { printf '%s\n' 'unrelated service'; }
        _codext_proxy_ready 8888
    ); then
        echo "  [ ok ] codext listener ownership"
    else
        fail "codext listener ownership"
    fi

    if CODEXT_TINYPROXY_CONFIG="$test_home/tinyproxy.conf" CODEXT_BIN="$test_home/codex" TER_SOURCE="$REPO" \
        bash --noprofile --norc -c '
            before_http=${HTTP_PROXY-__unset__}
            before_ssl=${SSL_CERT_FILE-__unset__}
            source "$TER_SOURCE/user/codex-network-fix.sh"
            tinyproxy() { return 0; }
            _codext_proxy_ready() { return 0; }
            codext || exit 1
            [ "${HTTP_PROXY-__unset__}" = "$before_http" ] &&
                [ "${SSL_CERT_FILE-__unset__}" = "$before_ssl" ]
        '; then
        echo "  [ ok ] codext environment scope"
    else
        fail "codext environment scope"
    fi
    rm -rf "$test_home"
}

check_tab_title() {
    local test_home
    # shellcheck disable=SC1090
    source "$REPO/user/tab_title.sh"
    test_home=$(mktemp -d "${TMPDIR:-/tmp}/ter-title.XXXXXX") || { fail "could not create tab_title test directory"; return; }

    # Test title control-character sanitization
    local raw_title expected_title
    raw_title=$(
        unset TMUX
        _ter_set_title "$(printf 'evil\007\033]2;pwn\007')"
    )
    expected_title=$(printf '\033]0;evil]2;pwn\007')
    if [ "$raw_title" != "$expected_title" ]; then
        fail "tab_title control character sanitization"
        rm -rf "$test_home"
        return
    fi

    # Test preexec command formatting
    local captured=""
    _ter_set_title() { captured="$1"; }
    _ter_where() { echo "phone"; }
    _ter_short_pwd() { echo "ter"; }

    _ter_preexec_title "   adb devices"
    if [ "$captured" != "📱 adb:devices / ter" ]; then
        fail "tab_title adb single subcommand parsing"
        rm -rf "$test_home"
        return
    fi

    _ter_preexec_title "adb -s 192.168.1.5:5555 shell"
    if [ "$captured" != "📱 adb:shell / ter" ]; then
        fail "tab_title adb options parsing"
        rm -rf "$test_home"
        return
    fi

    _ter_preexec_title "ssh -p 2222 user@oracle-server.internal"
    if [ "$captured" != "☁️ oracle-server" ]; then
        fail "tab_title ssh hostname parsing"
        rm -rf "$test_home"
        return
    fi

    _ter_preexec_title "vim -u NONE /tmp/test.txt"
    if [ "$captured" != "📱 vim / test.txt" ]; then
        fail "tab_title editor flag parsing"
        rm -rf "$test_home"
        return
    fi

    _ter_preexec_title "FOO=1 bar=2 claude"
    if [ "$captured" != "📱 claude / ter" ]; then
        fail "tab_title env prefix parsing"
        rm -rf "$test_home"
        return
    fi

    # Standalone variable assignment should not crash/loop and should not alter tab title
    captured="INITIAL_TITLE"
    _ter_preexec_title "A=1"
    if [ "$captured" != "INITIAL_TITLE" ]; then
        fail "tab_title standalone assignment handling"
        rm -rf "$test_home"
        return
    fi

    # SSH with -o Option=Value must not strip ssh command
    _ter_preexec_title "ssh -o StrictHostKeyChecking=no user@oracle-server.internal"
    if [ "$captured" != "☁️ oracle-server" ]; then
        fail "tab_title ssh options with equals parsing"
        rm -rf "$test_home"
        return
    fi

    # Generic command with arguments containing equals sign
    _ter_preexec_title "git config user.email=foo@bar.com"
    if [ "$captured" != "📱 git / ter" ]; then
        fail "tab_title command with equals argument parsing"
        rm -rf "$test_home"
        return
    fi

    # Wrapper + env assignment chaining
    _ter_preexec_title "sudo FOO=bar vim /tmp/test.txt"
    if [ "$captured" != "📱 vim / test.txt" ]; then
        fail "tab_title sudo + env wrapper parsing"
        rm -rf "$test_home"
        return
    fi

    # Wrapper with CLI flags
    _ter_preexec_title "sudo -u postgres psql"
    if [ "$captured" != "📱 psql / ter" ]; then
        fail "tab_title sudo with option argument parsing"
        rm -rf "$test_home"
        return
    fi

    _ter_preexec_title "sudo -E vim /tmp/test.txt"
    if [ "$captured" != "📱 vim / test.txt" ]; then
        fail "tab_title sudo with boolean flag parsing"
        rm -rf "$test_home"
        return
    fi

    _ter_preexec_title "env -i FOO=bar python3 script.py"
    if [ "$captured" != "📱 python3 / script.py" ]; then
        fail "tab_title env wrapper with flags parsing"
        rm -rf "$test_home"
        return
    fi

    _ter_preexec_title "sudo --preserve-env vim /tmp/test.txt"
    if [ "$captured" != "📱 vim / test.txt" ]; then
        fail "tab_title sudo with long flag parsing"
        rm -rf "$test_home"
        return
    fi

    _ter_preexec_title "sudo --user=postgres psql"
    if [ "$captured" != "📱 psql / ter" ]; then
        fail "tab_title sudo with long option equals parsing"
        rm -rf "$test_home"
        return
    fi

    _ter_preexec_title "sudo --user postgres psql"
    if [ "$captured" != "📱 psql / ter" ]; then
        fail "tab_title sudo with long option arg parsing"
        rm -rf "$test_home"
        return
    fi

    _ter_preexec_title "env --ignore-environment python3 script.py"
    if [ "$captured" != "📱 python3 / script.py" ]; then
        fail "tab_title env with long flag parsing"
        rm -rf "$test_home"
        return
    fi

    _ter_preexec_title "oc"
    if [ "$captured" != "📱 oc / ter" ]; then
        fail "tab_title opencode hijack"
        rm -rf "$test_home"
        return
    fi

    _ter_preexec_title "opencode run --continue"
    if [ "$captured" != "📱 opencode / ter" ]; then
        fail "tab_title opencode arg parsing"
        rm -rf "$test_home"
        return
    fi

    # Test PS1 escape cleanup (both string representation and literal escape bytes, OSC 0 and OSC 2)
    BASH_VERSION="5.2.0"
    PS1='\[\e]0;\u@\h: \w\a\]\[\033[01;32m\]\u@\h\[\033[00m\]:\w\$ '
    _ter_sanitize_ps1
    if [ "$PS1" != '\[\033[01;32m\]\u@\h\[\033[00m\]:\w\$ ' ]; then
        fail "tab_title PS1 title stripping (escaped OSC 0)"
        rm -rf "$test_home"
        return
    fi

    PS1='\[\e]2;\u@\h: \w\a\]\[\033[01;32m\]\u@\h\[\033[00m\]:\w\$ '
    _ter_sanitize_ps1
    if [ "$PS1" != '\[\033[01;32m\]\u@\h\[\033[00m\]:\w\$ ' ]; then
        fail "tab_title PS1 title stripping (escaped OSC 2)"
        rm -rf "$test_home"
        return
    fi

    PS1=$(printf '\033]0;ubuntu\007\\[\\033[01;32m\\]\\u@\\h\\[\\033[00m\\]:\\w\\$ ')
    _ter_sanitize_ps1
    if [ "$PS1" != '\[\033[01;32m\]\u@\h\[\033[00m\]:\w\$ ' ]; then
        fail "tab_title PS1 title stripping (literal bytes OSC 0)"
        rm -rf "$test_home"
        return
    fi

    PS1=$(printf '\033]2;ubuntu\007\\[\\033[01;32m\\]\\u@\\h\\[\\033[00m\\]:\\w\\$ ')
    _ter_sanitize_ps1
    if [ "$PS1" != '\[\033[01;32m\]\u@\h\[\033[00m\]:\w\$ ' ]; then
        fail "tab_title PS1 title stripping (literal bytes OSC 2)"
        rm -rf "$test_home"
        return
    fi

    # Test startup.conf without trailing newline
    mkdir -p "$test_home/.config/ter"
    printf 'TMUX_AUTOSTART=false\nWELCOME_DASHBOARD=false\nOPTIMIZE_STATUS=true' > "$test_home/.config/ter/startup.conf"
    (
        HOME="$test_home"
        source "$REPO/core/01-config.sh"
        if [ "$TMUX_AUTOSTART" != "false" ] || [ "$WELCOME_DASHBOARD" != "false" ] || [ "$OPTIMIZE_STATUS" != "true" ]; then
            exit 1
        fi
    )
    if [ $? -ne 0 ]; then
        fail "startup.conf parsing without trailing newline"
        rm -rf "$test_home"
        return
    fi

    echo "  [ ok ] tab_title behavioral validation"
    rm -rf "$test_home"
}

echo "TER smoke test — $REPO"
check_syntax
check_isolated_install
check_package_failure
check_adb_validation
check_sync_paths
check_codext_scope
check_tab_title
# zsh doesn't support --noprofile; use -f instead.
run_in bash "bash"
if command -v zsh >/dev/null 2>&1; then
    zsh_rc=0
    zsh -f -c '
        smoke_failed=0
        for dir in core network user; do
            for f in '"$REPO"'/$dir/*.sh; do
                [ -f "$f" ] || continue
                source "$f" 2>/dev/null || { echo "SOURCE_FAIL:$f"; smoke_failed=1; }
            done
        done
        for cmd in '"$EXPECT"'; do
            type "$cmd" >/dev/null 2>&1 || { echo "MISSING:$cmd"; smoke_failed=1; }
        done
        [ "$smoke_failed" -eq 0 ] || exit 1
        echo SMOKE_COMPLETE
    ' > "$SMOKE_OUTPUT" 2>&1 || zsh_rc=$?
    if [ "$zsh_rc" -ne 0 ] || ! grep -q '^SMOKE_COMPLETE$' "$SMOKE_OUTPUT" \
        || grep -q "^SOURCE_FAIL\|^MISSING" "$SMOKE_OUTPUT"; then
        echo "  [FAIL] zsh:"
        sed 's/^/    /' "$SMOKE_OUTPUT"
        FAIL=$((FAIL+1))
    else
        echo "  [ ok ] zsh"
    fi
    : > "$SMOKE_OUTPUT"
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
