#!/data/data/com.termux/files/usr/bin/env python3
"""
agy-account: Manage and rotate Antigravity CLI (agy) accounts/sessions.
"""

import sys
import os
import json
import base64
import shutil
import shlex
import subprocess
from pathlib import Path

AGY_DIR = Path(os.environ.get("AGY_DIR", Path.home() / ".gemini" / "antigravity-cli"))
TOKEN_FILE = AGY_DIR / "antigravity-oauth-token"
ACCOUNTS_DIR = AGY_DIR / "accounts"


def extract_email(data: dict) -> str:
    if data.get("id_token_email"):
        return data["id_token_email"]
    if data.get("email"):
        return data["email"]
    if data.get("id_token"):
        try:
            parts = data["id_token"].split(".")
            if len(parts) >= 2:
                payload_b64 = parts[1]
                payload_b64 += "=" * (-len(payload_b64) % 4)
                payload = json.loads(base64.urlsafe_b64decode(payload_b64))
                if payload.get("email"):
                    return payload["email"]
        except Exception:
            pass
    token_obj = data.get("token")
    if isinstance(token_obj, dict) and token_obj.get("email"):
        return token_obj["email"]
    return "unknown"


def get_default_alias(email: str) -> str:
    """Generate default alias from first 2 characters of email prefix."""
    if not email or email == "unknown":
        return "ac"
    prefix = email.split("@")[0].lower()
    clean = "".join(c for c in prefix if c.isalnum())
    if len(clean) >= 2:
        return clean[:2]
    return clean or "ac"


def get_token_info(token_path: Path):
    if not token_path.is_file():
        return None
    try:
        data = json.loads(token_path.read_text(encoding="utf-8"))
        email = extract_email(data)
        method = data.get("auth_method", "consumer")
        token_data = data.get("token", {}) if isinstance(data.get("token"), dict) else {}
        expiry = token_data.get("expiry", "unknown")
        return {
            "email": email,
            "auth_method": method,
            "expiry": expiry,
            "has_refresh": bool(token_data.get("refresh_token")),
        }
    except Exception as e:
        return {"error": str(e)}


def get_active_account():
    return get_token_info(TOKEN_FILE)


def list_saved_accounts():
    ACCOUNTS_DIR.mkdir(parents=True, exist_ok=True)
    accounts = []
    for entry in sorted(ACCOUNTS_DIR.iterdir()):
        if entry.is_dir():
            tfile = entry / "antigravity-oauth-token"
            if tfile.is_file():
                info = get_token_info(tfile)
                accounts.append((entry.name, info))
    return accounts


def save_current(name=None):
    if not TOKEN_FILE.is_file():
        print("❌ No active antigravity-oauth-token found.")
        return False
    info = get_token_info(TOKEN_FILE)
    if not info or "error" in info:
        print(f"❌ Invalid active token: {info}")
        return False

    account_name = name or get_default_alias(info.get("email", ""))
    dest_dir = ACCOUNTS_DIR / account_name
    dest_dir.mkdir(parents=True, exist_ok=True)
    dest_file = dest_dir / "antigravity-oauth-token"
    shutil.copy2(TOKEN_FILE, dest_file)
    try:
        os.chmod(dest_file, 0o600)
    except OSError:
        pass
    print(f"✅ Saved account '{account_name}' ({info['email']}) to {dest_dir}")
    return True


def save_active_back_to_profile():
    """Saves the current active token to its corresponding saved profile so refreshed tokens aren't lost."""
    if not TOKEN_FILE.is_file():
        return
    active_info = get_token_info(TOKEN_FILE)
    if not active_info or "email" not in active_info:
        return
    active_email = active_info["email"]
    for name, info in list_saved_accounts():
        if info and info.get("email") == active_email:
            dest_file = ACCOUNTS_DIR / name / "antigravity-oauth-token"
            shutil.copy2(TOKEN_FILE, dest_file)
            try:
                os.chmod(dest_file, 0o600)
            except OSError:
                pass
            break


def switch_to(target_name):
    target_dir = ACCOUNTS_DIR / target_name
    target_token = target_dir / "antigravity-oauth-token"
    if not target_token.is_file():
        # Match by alias, email, or prefix
        matched = None
        for name, info in list_saved_accounts():
            if info:
                email = info.get("email", "")
                if name == target_name or email == target_name or email.startswith(target_name):
                    matched = name
                    break
        if matched:
            target_token = ACCOUNTS_DIR / matched / "antigravity-oauth-token"
            target_name = matched
        else:
            print(f"❌ Account '{target_name}' not found in {ACCOUNTS_DIR}")
            return False

    save_active_back_to_profile()
    TOKEN_FILE.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(target_token, TOKEN_FILE)
    try:
        os.chmod(TOKEN_FILE, 0o600)
    except OSError:
        pass
    info = get_token_info(TOKEN_FILE)
    print(f"🔄 Switched to account '{target_name}' ({info.get('email', 'unknown') if info else 'unknown'})")
    return True


def rotate():
    accounts = list_saved_accounts()
    if not accounts:
        print("❌ No saved accounts found to rotate through.")
        return False
    if len(accounts) == 1:
        print(f"ℹ️ Only 1 account saved ('{accounts[0][0]}'). Add more accounts to rotate.")
        return True

    active = get_active_account()
    active_email = active.get("email") if active else None

    current_idx = -1
    for i, (name, info) in enumerate(accounts):
        if info and info.get("email") == active_email:
            current_idx = i
            break

    next_idx = (current_idx + 1) % len(accounts)
    next_name, _ = accounts[next_idx]
    print(f"Rotating from #{current_idx + 1} to #{next_idx + 1} of {len(accounts)} accounts...")
    return switch_to(next_name)


def parse_host_port(target=None, port_override=None):
    default_host = os.environ.get("AGY_SYNC_HOST") or os.environ.get("TNL_REMOTE") or "ubu"
    target_str = (target or default_host).strip()
    host = target_str
    port = port_override

    if ":" in target_str and not target_str.startswith("["):
        parts = target_str.split(":", 1)
        host = parts[0]
        port = port or parts[1]

    return host, port


def sync_accounts(target=None, port=None):
    host, port = parse_host_port(target, port_override=port)
    port_label = f" (port {port})" if port else ""
    print(f"📡 Syncing accounts to {host}{port_label}...")
    save_active_back_to_profile()

    ssh_opts = f"-p {port} " if port else ""
    scp_opts = f"-P {port} " if port else ""

    cmd_mkdir = f"ssh {ssh_opts}{host} 'mkdir -p ~/.gemini/antigravity-cli/accounts ~/.local/bin'"
    res = subprocess.run(cmd_mkdir, shell=True)
    if res.returncode != 0:
        print(f"❌ Could not reach {host} via SSH.")
        return False

    ACCOUNTS_DIR.mkdir(parents=True, exist_ok=True)
    cmd_scp = f"scp {scp_opts}-r {ACCOUNTS_DIR}/. {host}:~/.gemini/antigravity-cli/accounts/"
    subprocess.run(cmd_scp, shell=True)
    if TOKEN_FILE.is_file():
        cmd_scp_token = f"scp {scp_opts}{TOKEN_FILE} {host}:~/.gemini/antigravity-cli/antigravity-oauth-token"
        subprocess.run(cmd_scp_token, shell=True)

    script_path = Path(__file__).resolve()
    cmd_scp_script = f"scp {scp_opts}{script_path} {host}:~/.local/bin/agy-account"
    subprocess.run(cmd_scp_script, shell=True)

    remote_setup = (
        "chmod +x ~/.local/bin/agy-account && "
        "chmod 600 ~/.gemini/antigravity-cli/antigravity-oauth-token 2>/dev/null || true; "
        "chmod -R 600 ~/.gemini/antigravity-cli/accounts/* 2>/dev/null || true; "
        "if command -v termux-fix-shebang >/dev/null 2>&1; then "
        "termux-fix-shebang ~/.local/bin/agy-account; "
        "else "
        "sed -i '1s|^#!.*python.*|#!/usr/bin/env python3|' ~/.local/bin/agy-account 2>/dev/null || true; "
        "fi"
    )
    cmd_setup = f"ssh {ssh_opts}{host} {shlex.quote(remote_setup)}"
    subprocess.run(cmd_setup, shell=True)

    print(f"✅ Synced all accounts and tool to {host}!")
    return True


def delete_account(name):
    target = ACCOUNTS_DIR / name
    if target.is_dir():
        shutil.rmtree(target)
        print(f"🗑️ Removed saved account profile '{name}'")
        return True
    else:
        print(f"❌ Account '{name}' not found.")
        return False


def cmd_list():
    active = get_active_account()
    active_email = active.get("email") if active else None

    print("\n=== Active Account ===")
    if not active:
        print("  No active token found (not logged in).")
    elif "error" in active:
        print(f"  Error reading active token: {active['error']}")
    else:
        print(f"  Email:        {active['email']}")
        print(f"  Auth Method:  {active['auth_method']}")
        print(f"  Expiry:       {active['expiry']}")
        print(f"  Refreshable:  {'Yes' if active['has_refresh'] else 'No'}")

    accounts = list_saved_accounts()
    print(f"\n=== Saved Accounts ({len(accounts)}) ===")
    if not accounts:
        print("  No saved accounts yet. Run 'agy-account save [alias]' to save current session.")
    else:
        for name, info in accounts:
            marker = "👉 [ACTIVE]" if info and info.get("email") == active_email else "   "
            email = info.get("email", "unknown") if info else "unknown"
            expiry = info.get("expiry", "unknown") if info else "unknown"
            print(f" {marker} {name:<16} {email:<32} (expires: {expiry[:19]})")
    print()


def print_help():
    default_host = os.environ.get("AGY_SYNC_HOST") or os.environ.get("TNL_REMOTE") or "ubu"
    print("Usage:")
    print("  agy-account list                 List all saved accounts & active status")
    print("  agy-account save [alias]         Save current session (defaults to 2-letter email prefix, or custom alias)")
    print("  agy-account switch <alias/email> Switch active session to specified account")
    print("  agy-account next                 Rotate to next saved account (round-robin)")
    print("  agy-account rm <alias>           Remove a saved account profile")
    print(f"  agy-account sync [host] [-p port] Sync accounts & tool to remote host (default: {default_host})")


def main():
    if len(sys.argv) < 2:
        cmd_list()
        print_help()
        sys.exit(0)

    cmd = sys.argv[1].lower()
    if cmd in ["-h", "--help", "help"]:
        print_help()
        sys.exit(0)
    elif cmd in ["list", "status", "ls"]:
        cmd_list()
    elif cmd in ["save", "add"]:
        name = sys.argv[2] if len(sys.argv) > 2 else None
        if not save_current(name):
            sys.exit(1)
    elif cmd in ["switch", "use"]:
        if len(sys.argv) < 3:
            print("❌ Please specify account alias or email: agy-account switch <alias>")
            sys.exit(1)
        if not switch_to(sys.argv[2]):
            sys.exit(1)
    elif cmd in ["next", "rotate"]:
        if not rotate():
            sys.exit(1)
    elif cmd in ["rm", "remove", "delete"]:
        if len(sys.argv) < 3:
            print("❌ Please specify account alias: agy-account rm <alias>")
            sys.exit(1)
        if not delete_account(sys.argv[2]):
            sys.exit(1)
    elif cmd in ["sync", "sync-phone"]:
        target = None
        port = None
        args = sys.argv[2:]
        i = 0
        while i < len(args):
            arg = args[i]
            if arg in ["-p", "-P", "--port"]:
                if i + 1 < len(args):
                    port = args[i + 1]
                    i += 1
            elif not target:
                target = arg
            i += 1
        if not sync_accounts(target, port=port):
            sys.exit(1)
    else:
        print(f"Unknown command: {cmd}")
        print_help()
        sys.exit(1)


if __name__ == "__main__":
    main()
