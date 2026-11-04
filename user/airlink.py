#!/data/data/com.termux/files/usr/bin/env python3
"""airlink: Universal cross-device auth bridge & terminal URL toolkit.

Provides standalone modular tools and unified orchestration:
  airlink [options] [node] <command...>   Run CLI, capture auth URL, serve mobile gateway, inject code
  url-heal [options] [text]              Repair and un-mangle soft-wrapped & WhatsApp URLs
  qr [options] [text]                    Generate ASCII QR code (auto-heals URLs & clipboard)
  auth-code [options] [text]             Extract Google OAuth code from redirect URLs or chat text
"""

import argparse
import base64
import fcntl
import hmac
import http.server
import json
import os
import pty
import re
import secrets
import select
import shlex
import shutil
import signal
import socket
import socketserver
import struct
import subprocess
import sys
import threading
import time
import urllib.parse
from pathlib import Path


# ─────────────────────────────────────────────────────────────────────────────
# 1. Clipboard Helpers (Termux / Android / Desktop)
# ─────────────────────────────────────────────────────────────────────────────

def get_clipboard() -> str:
    """Read text from system/Termux clipboard."""
    if shutil.which("termux-clipboard-get"):
        try:
            res = subprocess.run(["termux-clipboard-get"], capture_output=True, text=True, timeout=3)
            if res.returncode == 0:
                return res.stdout or ""
        except Exception:
            pass
    if shutil.which("xclip"):
        try:
            res = subprocess.run(["xclip", "-selection", "clipboard", "-o"], capture_output=True, text=True, timeout=3)
            if res.returncode == 0:
                return res.stdout or ""
        except Exception:
            pass
    if shutil.which("wl-paste"):
        try:
            res = subprocess.run(["wl-paste"], capture_output=True, text=True, timeout=3)
            if res.returncode == 0:
                return res.stdout or ""
        except Exception:
            pass
    return ""


def set_clipboard(text: str) -> bool:
    """Write text to system/Termux clipboard."""
    if not text:
        return False
    if shutil.which("termux-clipboard-set"):
        try:
            res = subprocess.run(["termux-clipboard-set"], input=text.encode("utf-8"), timeout=3)
            return res.returncode == 0
        except Exception:
            pass
    if shutil.which("xclip"):
        try:
            res = subprocess.run(["xclip", "-selection", "clipboard"], input=text.encode("utf-8"), timeout=3)
            return res.returncode == 0
        except Exception:
            pass
    if shutil.which("wl-copy"):
        try:
            res = subprocess.run(["wl-copy"], input=text.encode("utf-8"), timeout=3)
            return res.returncode == 0
        except Exception:
            pass
    return False


def get_token_info(token_path: Path) -> dict:
    """Extract email and metadata from an antigravity oauth token file."""
    if not token_path.is_file():
        return {}
    try:
        data = json.loads(token_path.read_text(encoding="utf-8"))
        email = data.get("id_token_email") or data.get("email")
        if not email and data.get("id_token"):
            try:
                parts = data["id_token"].split(".")
                if len(parts) >= 2:
                    payload_b64 = parts[1] + "=" * (-len(parts[1]) % 4)
                    payload = json.loads(base64.urlsafe_b64decode(payload_b64))
                    email = payload.get("email")
            except Exception:
                pass
        if not email and isinstance(data.get("token"), dict):
            email = data["token"].get("email")
        return {"email": email or "unknown", "valid": True}
    except Exception:
        return {}


# ─────────────────────────────────────────────────────────────────────────────
# 2. URL Healer & Extractor
# ─────────────────────────────────────────────────────────────────────────────

def trim_url_artifacts(url: str) -> str:
    """Strip trailing punctuation, quotes, or box borders attached to a URL."""
    url = re.sub(r"[^A-Za-z0-9_\-./~:#@!$&*+,;=%?]+$", "", url)
    while url and url[-1] in ")].'\"`>,;":
        url = url[:-1]
    return url


def heal_url(raw: str) -> str:
    """Repair soft-wrapped, newline-split, or WhatsApp-damaged URLs.
    
    Reconstructs continuous single-line URL, removing accidental line-breaks,
    query-string whitespace, and terminal margin wraps.
    """
    if not raw:
        return ""
    text = raw.strip()
    m = re.search(r"https?://", text)
    if not m:
        return ""
    cand = text[m.start():]

    # Remove all carriage returns, newlines, and tabs
    cleaned = re.sub(r"[\r\n\t]+", "", cand)

    # In OAuth URLs, literal spaces inside query strings are wrapping artifacts
    # (real spaces in URLs are encoded as %20 or +). Join tokens across spaces.
    tokens = cleaned.split()
    healed = "".join(tokens)

    return trim_url_artifacts(healed)


def extract_url_from_stream(text: str) -> str | None:
    """Detect and extract full URLs from live terminal output streams."""
    if not text:
        return None

    # First look for standard full URLs
    matches = re.findall(r"https?://[A-Za-z0-9_\-./~:#@!$&*+,;=%?]+", text)
    if matches:
        keywords = ["oauth", "login", "auth", "token", "code", "device", "state=", "signin"]
        for m in reversed(matches):
            trimmed = trim_url_artifacts(m)
            if not trimmed.endswith(("&", "=", "?")):
                if any(k in trimmed.lower() for k in keywords):
                    return trimmed
        trimmed_last = trim_url_artifacts(matches[-1])
        if not trimmed_last.endswith(("&", "=", "?")):
            return trimmed_last

    # Check soft-wrapped terminal chunks
    lines = [l.strip() for l in text.splitlines() if l.strip()]
    reconstructed = []
    in_url = False
    for line in lines:
        if line.startswith(("http://", "https://")):
            reconstructed.append(line)
            in_url = True
        elif in_url:
            if " " not in line and any(c in line for c in ["=", "&", "/", "%", "?"]):
                reconstructed[-1] += line
            elif line.startswith(("state=", "client_id=", "redirect_uri=", "code=", "access_type=")):
                reconstructed[-1] += line
            else:
                in_url = False
    for r in reconstructed:
        cand = trim_url_artifacts(r)
        if cand:
            return cand

    # Fallback: compact whitespace strip
    healed = heal_url(text)
    if healed:
        return healed

    return None


# ─────────────────────────────────────────────────────────────────────────────
# 3. Auth Code Extractor
# ─────────────────────────────────────────────────────────────────────────────

def extract_auth_code(text: str) -> str:
    """Extract Google OAuth authorization code from query strings, URLs, or chat text."""
    if not text:
        return ""
    clean = text.strip()

    # 1. Search for code= parameter in callback URL
    m = re.search(r"[?&]code=([^&\s]+)", clean)
    if m:
        val = urllib.parse.unquote(m.group(1)).strip()
        if re.match(r"^[A-Za-z0-9_\-./+=]{10,512}$", val):
            return val

    # 2. Search for Google OAuth code pattern: 4/0A... or 4/...
    m = re.search(r"4/[A-Za-z0-9_\-]{10,512}", clean)
    if m:
        return m.group(0).strip()

    # 3. Raw authorization token (must not contain internal whitespace or control characters)
    if not re.search(r"\s", clean):
        if len(clean) >= 10 and re.match(r"^[A-Za-z0-9_\-./+=]{10,512}$", clean):
            return clean

    return ""


# ─────────────────────────────────────────────────────────────────────────────
# 4. QR Code Engine
# ─────────────────────────────────────────────────────────────────────────────

def render_qr(data: str, invert: bool = True, border: int = 1) -> bool:
    """Display ASCII QR code in the terminal with newline and column safety."""
    try:
        import qrcode
        import io
        qr = qrcode.QRCode(border=border)
        qr.add_data(data)
        cols = shutil.get_terminal_size((80, 24)).columns
        sio = io.StringIO()
        qr.print_ascii(out=sio, invert=invert)
        qr_str = sio.getvalue()
        lines = qr_str.splitlines()
        max_w = max(len(l) for l in lines) if lines else 0
        if cols < max_w:
            sys.stdout.write(f"\r\n\033[1;33m⚠️ Terminal width ({cols} cols) is narrower than QR code ({max_w} cols).\033[0m\r\n\033[0;33m   Pinch/zoom out font for Phone B to scan cleanly.\033[0m\r\n\r\n")
        for l in lines:
            sys.stdout.write(l + "\r\n")
        sys.stdout.flush()
        return True
    except ImportError:
        # Fallback to command-line qr if available
        if shutil.which("qr"):
            subprocess.run(["qr", data])
            return True
        sys.stderr.write("❌ python 'qrcode' package not installed. Run: pip install qrcode\r\n")
        return False
    except Exception as e:
        sys.stderr.write(f"❌ Failed to render QR: {e}\r\n")
        return False


# ─────────────────────────────────────────────────────────────────────────────
# 5. Network Discovery (LAN / Hotspot / Tailscale)
# ─────────────────────────────────────────────────────────────────────────────

EXCLUDE_IFACE_PREFIXES = ("rmnet", "vgate", "tun", "tap", "dummy", "ppp", "p2p", "sit", "ip_vti", "ip6", "lo")

def get_lan_ip() -> str | None:
    """Discover local reachable IP (Wi-Fi, hotspot gateway, or Tailscale route).
    
    Excludes VPN tunnels (vgate, tun, tap) and cellular data interfaces (rmnet).
    Returns None if no reachable local interface is active.
    """
    # 1. Hotspot & Wi-Fi interfaces (highest priority for cross-phone connectivity)
    try:
        res = subprocess.run(["ifconfig"], capture_output=True, text=True, timeout=2)
        out = res.stdout or ""
        blocks = out.split("\n\n")
        ifaces = {}
        for block in blocks:
            lines = block.strip().splitlines()
            if not lines:
                continue
            name = lines[0].split(":")[0].strip()
            m = re.search(r"inet\s+([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)", block)
            if m:
                ifaces[name] = m.group(1)

        # Hotspot & Wi-Fi interfaces
        for pref in ["ap0", "wlan0", "swlan0", "rndis0", "wlan1"]:
            if pref in ifaces and not ifaces[pref].startswith("127."):
                return ifaces[pref]

        # Standard Android hotspot IP 192.168.43.1 or private 192.168.x.x (on physical non-excluded interface)
        for name, ip in ifaces.items():
            if any(name.startswith(ex) for ex in EXCLUDE_IFACE_PREFIXES):
                continue
            if ip.startswith("192.168.43.") or ip.startswith("192.168."):
                return ip

        # Tailscale VPN (valid for cross-device tailnet connectivity)
        for name, ip in ifaces.items():
            if ip.startswith("100.") or "tailscale" in name:
                return ip

        # Non-cellular private LAN (e.g. 10.x, 172.16-31.x on physical LAN interface)
        for name, ip in ifaces.items():
            if any(name.startswith(ex) for ex in EXCLUDE_IFACE_PREFIXES):
                continue
            if ip.startswith("10.") or (ip.startswith("172.") and 16 <= int(ip.split(".")[1]) <= 31 and not ip.startswith("172.30.")):
                return ip
    except Exception:
        pass

    # 2. Outbound route socket probe (fallback, ensuring not a VPN or cellular tunnel)
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        if ip and not ip.startswith("127.") and not ip.startswith("172.30.") and (ip.startswith("192.168.") or ip.startswith("10.") or ip.startswith("100.")):
            return ip
    except Exception:
        pass

    return None


# ─────────────────────────────────────────────────────────────────────────────
# 6. AirLink Mobile Gateway (Web Server)
# ─────────────────────────────────────────────────────────────────────────────

class AirLinkGatewayHandler(http.server.BaseHTTPRequestHandler):
    target_url: str = ""
    command_name: str = "Command"
    auth_token: str = ""
    on_code_callback = None

    def log_message(self, format, *args):
        # Quiet HTTP access logging
        pass

    def _verify_token(self, supplied_token: str) -> bool:
        return bool(self.auth_token) and hmac.compare_digest(supplied_token or "", self.auth_token)

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        qs = urllib.parse.parse_qs(parsed.query)
        supplied_token = qs.get("token", [""])[0]

        if not self._verify_token(supplied_token):
            self.send_response(403)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.end_headers()
            self.wfile.write(b"403 Forbidden: Invalid or missing AirLink session token.\n")
            return

        html = f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
<title>AirLink Auth Gateway</title>
<style>
  * {{ box-sizing: border-box; margin: 0; padding: 0; }}
  body {{
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
    background: #101216;
    color: #e4e7eb;
    display: flex;
    justify-content: center;
    align-items: center;
    min-height: 100vh;
    padding: 16px;
  }}
  .card {{
    background: #181b21;
    border: 1px solid #282d37;
    border-radius: 16px;
    padding: 24px;
    max-width: 440px;
    width: 100%;
    box-shadow: 0 12px 32px rgba(0,0,0,0.4);
    text-align: center;
  }}
  .badge {{
    display: inline-block;
    padding: 4px 10px;
    background: #1e293b;
    color: #38bdf8;
    border-radius: 12px;
    font-size: 12px;
    font-weight: 600;
    margin-bottom: 12px;
    letter-spacing: 0.5px;
  }}
  h1 {{ font-size: 20px; font-weight: 700; margin-bottom: 8px; color: #f8fafc; }}
  p {{ font-size: 13px; color: #94a3b8; line-height: 1.5; margin-bottom: 18px; }}
  .btn-login {{
    display: block;
    width: 100%;
    padding: 14px 20px;
    background: #2563eb;
    color: #ffffff;
    text-decoration: none;
    border-radius: 10px;
    font-weight: 600;
    font-size: 15px;
    margin-bottom: 22px;
    box-shadow: 0 4px 14px rgba(37,99,235,0.3);
  }}
  .divider {{
    display: flex;
    align-items: center;
    color: #475569;
    font-size: 11px;
    font-weight: 700;
    text-transform: uppercase;
    margin: 18px 0;
  }}
  .divider::before, .divider::after {{
    content: ""; flex: 1; border-bottom: 1px solid #282d37;
  }}
  .divider span {{ padding: 0 10px; }}
  textarea {{
    width: 100%;
    height: 80px;
    background: #0d1117;
    color: #f1f5f9;
    border: 1px solid #334155;
    border-radius: 10px;
    padding: 12px;
    font-size: 13px;
    font-family: monospace;
    resize: none;
    margin-bottom: 14px;
    outline: none;
  }}
  textarea:focus {{ border-color: #38bdf8; }}
  .btn-submit {{
    width: 100%;
    padding: 14px;
    background: #10b981;
    color: #064e3b;
    border: none;
    border-radius: 10px;
    font-size: 15px;
    font-weight: 700;
    cursor: pointer;
    box-shadow: 0 4px 14px rgba(16,185,129,0.25);
  }}
</style>
</head>
<body>
<div class="card">
  <div class="badge">⚡ AIRLINK AUTH GATEWAY</div>
  <h1>{self.command_name} Sign-In</h1>
  <p>Step 1: Open Google authentication in your browser with your subscription account:</p>
  <a class="btn-login" href="{self.target_url}" target="_blank">🔑 Open Google Login</a>
  
  <div class="divider"><span>Step 2</span></div>
  <p>When login completes, copy the code (or redirect link) and paste below:</p>
  <form method="POST" action="/submit">
    <input type="hidden" name="token" value="{self.auth_token}">
    <textarea name="code" placeholder="Paste authorization code or localhost URL here..." required></textarea>
    <button class="btn-submit" type="submit">🚀 Deliver Code to Terminal</button>
  </form>
</div>
</body>
</html>"""
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.end_headers()
        self.wfile.write(html.encode("utf-8"))

    def do_POST(self):
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path == "/submit":
            length = int(self.headers.get("Content-Length", 0))
            if length <= 0 or length > 8192:
                self.send_response(400)
                self.end_headers()
                return

            body = self.rfile.read(length).decode("utf-8", errors="ignore")
            params = urllib.parse.parse_qs(body)
            supplied_token = params.get("token", [""])[0] or urllib.parse.parse_qs(parsed.query).get("token", [""])[0]

            if not self._verify_token(supplied_token):
                self.send_response(403)
                self.send_header("Content-Type", "text/plain; charset=utf-8")
                self.end_headers()
                self.wfile.write(b"403 Forbidden: Invalid or missing AirLink session token.\n")
                return

            raw_input = params.get("code", [""])[0]
            clean_code = extract_auth_code(raw_input)

            # Strict validation: must match valid token character set and bounds, no control characters
            if not clean_code or not re.match(r"^[A-Za-z0-9_\-./+=]{10,512}$", clean_code):
                self.send_response(400)
                self.send_header("Content-Type", "text/html; charset=utf-8")
                self.end_headers()
                self.wfile.write(b"<html><body style=\"background:#101216;color:#f87171;padding:30px;font-family:sans-serif;\"><h2>400 Bad Request</h2><p>Invalid authorization code format. Please copy the code and try again.</p></body></html>")
                return

            if self.on_code_callback:
                self.on_code_callback(clean_code)

            resp = """<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Code Delivered</title>
<style>
  body { background: #101216; color: #10b981; font-family: -apple-system, sans-serif; display: flex; justify-content: center; align-items: center; min-height: 100vh; text-align: center; padding: 20px; }
  .box { background: #181b21; border: 1px solid #10b981; border-radius: 16px; padding: 32px; max-width: 380px; }
  h2 { margin-bottom: 10px; }
  p { color: #94a3b8; font-size: 14px; }
</style>
</head>
<body>
<div class="box">
  <h2>✔ Code Delivered!</h2>
  <p>Terminal has received the code and is authenticating now. You can close this tab.</p>
</div>
</body>
</html>"""
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.end_headers()
            self.wfile.write(resp.encode("utf-8"))


class AirLinkServer:
    def __init__(self, target_url: str, command_name: str, on_code_received):
        self.target_url = target_url
        self.command_name = command_name
        self.on_code_received = on_code_received
        self.auth_token = secrets.token_urlsafe(16)
        self.server = None
        self.thread = None
        self.port = 8888
        self.lan_ip = get_lan_ip() or "127.0.0.1"

    def start(self):
        callback_func = staticmethod(self.on_code_received) if self.on_code_received else None
        handler_cls = type(
            "CustomAirLinkHandler",
            (AirLinkGatewayHandler,),
            {
                "target_url": self.target_url,
                "command_name": self.command_name,
                "on_code_callback": callback_func,
                "auth_token": self.auth_token,
            },
        )
        for attempt_port in range(8888, 8910):
            try:
                self.server = socketserver.TCPServer(("0.0.0.0", attempt_port), handler_cls)
                self.port = attempt_port
                break
            except OSError:
                continue

        if not self.server:
            return None

        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        return f"http://{self.lan_ip}:{self.port}/?token={self.auth_token}"

    def stop(self):
        if self.server:
            try:
                self.server.shutdown()
                self.server.server_close()
            except Exception:
                pass


# ─────────────────────────────────────────────────────────────────────────────
# 7. Main Command Orchestrator (airlink runner)
# ─────────────────────────────────────────────────────────────────────────────

def trigger_agy_account_save():
    """Trigger agy-account save if active token was created/updated."""
    agy_script = Path.home() / ".local" / "bin" / "agy-account"
    if not agy_script.is_file():
        agy_script = Path(__file__).parent / "agy-account.py"
    if agy_script.is_file():
        try:
            print("\n💾 Auto-saving token to agy-account profiles...")
            subprocess.run([sys.executable, str(agy_script), "save"])
            print("💡 Tip: Run 'agy-account sync ubu' to synchronize profiles with your VM.\n")
        except Exception:
            pass


def run_airlink(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(
        prog="airlink",
        description="AirLink: Universal cross-device auth bridge & terminal URL toolkit",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("args", nargs="*", help="Node and/or command to execute (e.g. agy, ubu agy, gh auth)")
    parser.add_argument("--qr", action="store_true", help="Render OAuth QR code directly in terminal (skip web gateway)")
    parser.add_argument("--open", action="store_true", help="Open captured URL in local phone browser")
    parser.add_argument("--clip", action="store_true", help="Silently copy captured URL to Android clipboard")
    parser.add_argument("--local", action="store_true", help="Force local execution in Termux")
    parser.add_argument("--no-save", action="store_true", help="Do not auto-save token with agy-account")
    parser.add_argument("--reauth", "--login", "--new", dest="reauth", action="store_true", help="Force new account sign-in flow (backs up active session)")

    opts, remaining = parser.parse_known_args(argv)
    raw_args = list(opts.args) + list(remaining)

    if not raw_args:
        parser.print_help()
        token_path = Path.home() / ".gemini" / "antigravity-cli" / "antigravity-oauth-token"
        if token_path.is_file():
            info = get_token_info(token_path)
            if info.get("email"):
                print(f"\n\033[1;32m● Active agy session:\033[0m \033[1m{info['email']}\033[0m")
        print("\nExamples:")
        print("  airlink agy                 Run agy CLI with AirLink")
        print("  airlink --reauth agy        Log in with a new Google account (Phone B or local)")
        print("  airlink --qr agy            Direct terminal QR code mode")
        print("  airlink ubu agy             Run on remote node 'ubu'")
        print("  airlink gh auth login       GitHub device flow across phones")
        print("  airlink --open <cmd>        Open captured URL directly on phone browser")
        print("\nStandalone Tools:")
        print("  url-heal                    Fix broken URLs in clipboard")
        print("  qr                          Render QR code for clipboard/text")
        print("  auth-code                   Extract OAuth code from clipboard URL")
        return 0

    # Support 'login' or 'reauth' subcommand
    if raw_args[0] in ("login", "reauth"):
        opts.reauth = True
        raw_args = raw_args[1:]
        if not raw_args:
            raw_args = ["agy"]

    first = raw_args[0]
    remote_hosts = []
    ssh_config = Path.home() / ".ssh" / "config"
    if ssh_config.is_file():
        try:
            for line in ssh_config.read_text().splitlines():
                if line.strip().startswith("Host "):
                    for h in line.strip().split()[1:]:
                        if "*" not in h:
                            remote_hosts.append(h)
        except Exception:
            pass

    is_remote = False
    target_node = None
    cmd_tokens = []

    if not opts.local and first in remote_hosts:
        is_remote = True
        target_node = first
        cmd_tokens = raw_args[1:]
    else:
        cmd_tokens = raw_args

    if not cmd_tokens:
        cmd_tokens = ["agy"]

    cmd_str = " ".join(cmd_tokens)
    cmd_name = cmd_tokens[0] if cmd_tokens else "cli"

    print(f"\033[1;36m⚡ AirLink Launching:\033[0m \033[1m{cmd_str}\033[0m" + (f" (on @{target_node})" if is_remote else " (local)"))

    # Check initial token modification time for agy
    token_path = Path.home() / ".gemini" / "antigravity-cli" / "antigravity-oauth-token"
    token_mtime_before = token_path.stat().st_mtime if token_path.is_file() else 0
    backup_token_path = None

    # Handle agy authentication check and --reauth / qr login flow
    is_login_flow = opts.reauth or opts.qr or (cmd_tokens and cmd_tokens[0] in ("login", "reauth"))

    if not is_remote and cmd_name in ("agy", "antigravity"):
        if token_path.is_file():
            info = get_token_info(token_path)
            email = info.get("email", "unknown")
            if is_login_flow:
                # Ensure existing session is saved into agy-account so it's not lost
                trigger_agy_account_save()
                backup_token_path = token_path.parent / f".reauth_backup_{os.getpid()}"
                try:
                    shutil.copy2(token_path, backup_token_path)
                    token_path.unlink()
                    print(f"\033[1;36m🔑 AirLink: Starting fresh QR sign-in for agy...\033[0m\n\033[0;32m  ✔ Current active session ({email}) saved in agy-account.\033[0m\n\033[0;36m  ⚡ Generating Google OAuth QR code for Phone B...\033[0m\n")
                except Exception as e:
                    print(f"⚠️ Failed to isolate token for reauth: {e}")
            else:
                print(f"\033[1;33mℹ️ agy is already logged in as {email}.\033[0m\n\033[0;36m   • Resuming active session...\n   • To log in with a new account via QR: \033[1mairlink qr agy\033[0m\n")

    # Prepare command execution (ensure remote PATH includes standard binary locations)
    if is_remote:
        exec_args = ["ssh", "-tt", target_node, f"export PATH=\"$HOME/.local/bin:$HOME/bin:$PATH\"; cd ~ && {cmd_str}"]
    else:
        exec_args = cmd_tokens

    is_interactive = sys.stdin.isatty() and sys.stdout.isatty()
    master_fd, slave_fd = pty.openpty()

    # Forward terminal dimensions if interactive
    if is_interactive:
        try:
            ws = fcntl.ioctl(sys.stdin.fileno(), termios.TIOCGWINSZ, b"\x00" * 8)
            fcntl.ioctl(slave_fd, termios.TIOCSWINSZ, ws)
            fcntl.ioctl(master_fd, termios.TIOCSWINSZ, ws)
        except Exception:
            pass

        def sigwinch_handler(signum, frame):
            try:
                ws = fcntl.ioctl(sys.stdin.fileno(), termios.TIOCGWINSZ, b"\x00" * 8)
                fcntl.ioctl(master_fd, termios.TIOCSWINSZ, ws)
            except Exception:
                pass

        try:
            signal.signal(signal.SIGWINCH, sigwinch_handler)
        except Exception:
            pass

    proc = subprocess.Popen(
        exec_args,
        stdin=slave_fd,
        stdout=slave_fd,
        stderr=slave_fd,
        close_fds=True,
    )
    os.close(slave_fd)

    # Set raw/cbreak terminal mode on parent stdin so escape keys, arrows, and characters pass through
    old_tty = None
    if is_interactive:
        try:
            old_tty = termios.tcgetattr(sys.stdin.fileno())
            new_tty = list(old_tty)
            tty.cfmakeraw(new_tty)
            new_tty[1] |= termios.OPOST  # Maintain newline expansion (\n -> \r\n)
            termios.tcsetattr(sys.stdin.fileno(), termios.TCSADRAIN, new_tty)
        except Exception:
            old_tty = None

    buf = []
    lock = threading.Lock()
    url_captured = threading.Event()
    code_injected = threading.Event()
    gateway_server = None

    def deliver_code_to_proc(code: str):
        if not code or code_injected.is_set():
            return
        safe_code = code.strip()
        # Defense-in-depth: only permit standard OAuth code characters
        if not re.match(r"^[A-Za-z0-9_\-./+=]{10,512}$", safe_code):
            return
        code_injected.set()
        try:
            os.write(master_fd, (safe_code + "\r\n").encode("utf-8"))
            sys.stdout.buffer.write(b"\r\n\033[1;32m\xe2\x9c\x94 Code delivered to terminal!\033[0m\r\n")
            sys.stdout.buffer.flush()
        except OSError:
            pass

    def on_url_found(url: str):
        nonlocal gateway_server
        if url_captured.is_set():
            return
        url_captured.set()
        clean = heal_url(url)
        set_clipboard(clean)

        if opts.clip:
            sys.stdout.write(f"\r\n\033[1;32m✔ Clean URL copied to clipboard!\033[0m\r\n")
            sys.stdout.flush()
            return

        if opts.open:
            sys.stdout.write(f"\r\n\033[1;32m✔ Opening URL on phone browser...\033[0m\r\n")
            sys.stdout.flush()
            if shutil.which("termux-open-url"):
                subprocess.Popen(["termux-open-url", clean], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            return

        lan_ip = get_lan_ip()
        # If explicit QR mode OR device has no reachable LAN/Hotspot IP, use direct terminal QR
        if opts.qr or not lan_ip:
            if not opts.qr and not lan_ip:
                sys.stdout.write(f"\r\n\033[1;33mℹ️ No local Wi-Fi / Hotspot detected (device is on cellular data).\033[0m\r\n\033[1;36m📱 Switching to Direct Terminal QR Mode for Phone B:\033[0m\r\n")
            else:
                sys.stdout.write(f"\r\n\033[1;32m✔ Scan QR with Phone B to Authenticate:\033[0m\r\n")
            render_qr(clean, invert=True)
            sys.stdout.write(f"  \033[1;36m{clean}\033[0m\r\n")
            sys.stdout.write(f"\r\n\033[1;33m👉 When Phone B displays the code, paste it below:\033[0m\r\n")
            sys.stdout.flush()
            return

        # Default: Web Gateway Mode (LAN IP is reachable)
        gateway_server = AirLinkServer(clean, cmd_name, deliver_code_to_proc)
        gateway_url = gateway_server.start()
        if gateway_url:
            set_clipboard(gateway_url)
            sys.stdout.write(f"\r\n\033[1;32m⚡ AirLink Gateway Active! Point Phone B camera at the QR code:\033[0m\r\n")
            render_qr(gateway_url, invert=True)
            sys.stdout.write(f"  \033[1;36mPortal Link:\033[0m \033[1m{gateway_url}\033[0m\r\n")
            sys.stdout.write(f"  \033[1;33m1. Scan with Phone B ➔ Tap Login ➔ Copy Code\033[0m\r\n")
            sys.stdout.write(f"  \033[1;33m2. Paste code into the web page to auto-deliver\033[0m\r\n\r\n")
            sys.stdout.flush()
        else:
            # Fallback to direct QR
            render_qr(clean, invert=True)

    try:
        stdin_active = True
        while True:
            rlist = [master_fd]
            if stdin_active:
                rlist.append(sys.stdin.fileno())

            r, _, _ = select.select(rlist, [], [], 0.05)

            # Process output from child process
            if master_fd in r:
                try:
                    data = os.read(master_fd, 4096)
                except OSError:
                    data = b""
                if not data:
                    break
                sys.stdout.buffer.write(data)
                sys.stdout.buffer.flush()

                text = data.decode("utf-8", errors="ignore")
                with lock:
                    buf.append(text)
                    if len(buf) > 50:
                        buf.pop(0)
                if not url_captured.is_set():
                    cand = extract_url_from_stream(text)
                    if not cand and len(buf) >= 2:
                        cand = extract_url_from_stream("".join(buf[-5:]))
                    if cand:
                        on_url_found(cand)

            # User input from terminal
            if stdin_active and sys.stdin.fileno() in r:
                try:
                    inp = os.read(sys.stdin.fileno(), 1024)
                    if not inp:
                        stdin_active = False
                    else:
                        os.write(master_fd, inp)
                except OSError:
                    stdin_active = False

            if proc.poll() is not None:
                # Drain remaining output before exiting
                while True:
                    r_drain, _, _ = select.select([master_fd], [], [], 0.05)
                    if master_fd in r_drain:
                        try:
                            drain_data = os.read(master_fd, 4096)
                            if not drain_data:
                                break
                            sys.stdout.buffer.write(drain_data)
                            sys.stdout.buffer.flush()
                            text = drain_data.decode("utf-8", errors="ignore")
                            with lock:
                                buf.append(text)
                            if not url_captured.is_set():
                                cand = extract_url_from_stream(text)
                                if cand:
                                    on_url_found(cand)
                        except OSError:
                            break
                    else:
                        break
                break
    finally:
        # Restore terminal mode immediately upon exit
        if old_tty is not None:
            try:
                termios.tcsetattr(sys.stdin.fileno(), termios.TCSADRAIN, old_tty)
            except Exception:
                pass

    rc = proc.wait()
    try:
        os.close(master_fd)
    except OSError:
        pass

    if gateway_server:
        gateway_server.stop()

    # Reauth / Token cleanup & auto-save
    if not is_remote and cmd_name in ("agy", "antigravity"):
        if token_path.is_file() and token_path.stat().st_mtime > token_mtime_before:
            if not opts.no_save:
                trigger_agy_account_save()
            if backup_token_path and backup_token_path.is_file():
                try:
                    backup_token_path.unlink()
                except OSError:
                    pass
        else:
            if backup_token_path and backup_token_path.is_file():
                try:
                    shutil.move(str(backup_token_path), str(token_path))
                    print("\n\033[0;32mℹ️ Restored previous active account session.\033[0m")
                except Exception:
                    pass
    elif not opts.no_save and not is_remote and ("agy" in cmd_tokens or "antigravity" in cmd_tokens):
        if token_path.is_file() and token_path.stat().st_mtime > token_mtime_before:
            trigger_agy_account_save()

    return rc


# ─────────────────────────────────────────────────────────────────────────────
# 8. Standalone Subcommands
# ─────────────────────────────────────────────────────────────────────────────

def run_url_heal_cli(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(
        prog="url-heal",
        description="Repair soft-wrapped, newline-split, or WhatsApp-broken URLs",
    )
    parser.add_argument("url", nargs="?", help="URL text to heal (reads clipboard if omitted)")
    parser.add_argument("-c", "--clip", action="store_true", help="Copy healed URL to clipboard")
    parser.add_argument("-q", "--quiet", action="store_true", help="Do not print, only copy to clipboard")

    opts = parser.parse_args(argv)
    raw = opts.url
    if not raw:
        if not sys.stdin.isatty():
            raw = sys.stdin.read()
        else:
            raw = get_clipboard()
            opts.clip = True

    if not raw:
        sys.stderr.write("❌ No URL provided and clipboard is empty.\n")
        return 1

    healed = heal_url(raw)
    if not healed:
        sys.stderr.write("❌ No valid URL pattern found in input.\n")
        return 1

    if opts.clip:
        set_clipboard(healed)
    if not opts.quiet:
        print(healed)
    return 0


def run_qr_cli(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(
        prog="qr",
        description="Universal terminal ASCII QR code generator",
    )
    parser.add_argument("text", nargs="?", help="Text or URL to render (reads clipboard if omitted)")
    parser.add_argument("-c", "--clip", action="store_true", help="Copy clean text to clipboard")
    parser.add_argument("--raw", action="store_true", help="Do not auto-heal URLs, render exact text")
    parser.add_argument("-i", "--invert", action="store_true", default=True, help="Invert module colors (default for dark terminals)")
    parser.add_argument("-s", "--small", action="store_true", help="Compact single-character border")

    opts = parser.parse_args(argv)
    raw = opts.text
    if not raw:
        if not sys.stdin.isatty():
            raw = sys.stdin.read()
        else:
            raw = get_clipboard()
            opts.clip = True

    if not raw:
        sys.stderr.write("❌ No text provided and clipboard is empty.\n")
        return 1

    final_data = raw.strip()
    if not opts.raw and ("http://" in final_data or "https://" in final_data):
        healed = heal_url(final_data)
        if healed:
            final_data = healed

    if opts.clip:
        set_clipboard(final_data)

    success = render_qr(final_data, invert=opts.invert, border=1)
    return 0 if success else 1


def run_auth_code_cli(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(
        prog="auth-code",
        description="Extract Google OAuth authorization code from callback URLs or chat text",
    )
    parser.add_argument("text", nargs="?", help="URL or text containing the code (reads clipboard if omitted)")
    parser.add_argument("-c", "--clip", action="store_true", help="Copy clean code to clipboard")
    parser.add_argument("-q", "--quiet", action="store_true", help="Do not print, only copy to clipboard")

    opts = parser.parse_args(argv)
    raw = opts.text
    if not raw:
        if not sys.stdin.isatty():
            raw = sys.stdin.read()
        else:
            raw = get_clipboard()
            opts.clip = True

    if not raw:
        sys.stderr.write("❌ No text provided and clipboard is empty.\n")
        return 1

    code = extract_auth_code(raw)
    if not code:
        sys.stderr.write("❌ Could not extract authorization code from input.\n")
        return 1

    if opts.clip:
        set_clipboard(code)
    if not opts.quiet:
        print(code)
    return 0


# ─────────────────────────────────────────────────────────────────────────────
# 9. Main Dispatcher
# ─────────────────────────────────────────────────────────────────────────────

def main():
    prog = os.path.basename(sys.argv[0])
    args = sys.argv[1:]

    # Dispatch based on symlink executable name
    if prog in ("url-heal", "heal"):
        sys.exit(run_url_heal_cli(args))
    elif prog == "qr":
        sys.exit(run_qr_cli(args))
    elif prog in ("auth-code", "code"):
        sys.exit(run_auth_code_cli(args))

    # Dispatch based on first subcommand argument
    if args and args[0] in ("heal", "url-heal"):
        sys.exit(run_url_heal_cli(args[1:]))
    elif args and args[0] == "qr":
        if len(args) > 1 and not args[1].startswith("http"):
            # 'airlink qr <command...>' -> run with --qr option
            sys.exit(run_airlink(["--qr"] + args[1:]))
        else:
            sys.exit(run_qr_cli(args[1:]))
    elif args and args[0] in ("code", "auth-code"):
        sys.exit(run_auth_code_cli(args[1:]))
    elif args and args[0] in ("logout", "signout"):
        token_path = Path.home() / ".gemini" / "antigravity-cli" / "antigravity-oauth-token"
        if token_path.is_file():
            info = get_token_info(token_path)
            trigger_agy_account_save()
            token_path.unlink()
            print(f"\n\033[1;32m✅ Logged out from agy ({info.get('email', 'account')}).\033[0m")
            print("💡 Active token safely preserved in agy-account profiles.")
            print("   • Run 'agy-account switch <alias>' to restore a saved session.")
            print("   • Run 'airlink qr agy' to log in with a new Google account.\n")
        else:
            print("ℹ️ No active agy session found.")
        sys.exit(0)
    else:
        sys.exit(run_airlink(args))


if __name__ == "__main__":
    main()
