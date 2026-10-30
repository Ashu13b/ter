#!/data/data/com.termux/files/usr/bin/env python3
"""airlink: Universal cross-device auth bridge & terminal URL toolkit.

Provides standalone modular tools and unified orchestration:
  airlink [options] [node] <command...>   Run CLI, capture auth URL, serve mobile gateway, inject code
  url-heal [options] [text]              Repair and un-mangle soft-wrapped & WhatsApp URLs
  qr [options] [text]                    Generate ASCII QR code (auto-heals URLs & clipboard)
  auth-code [options] [text]             Extract Google OAuth code from redirect URLs or chat text
"""

import argparse
import http.server
import json
import os
import pty
import re
import select
import shlex
import shutil
import socket
import socketserver
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
        return urllib.parse.unquote(m.group(1)).strip()

    # 2. Search for Google OAuth code pattern: 4/0A... or 4/...
    m = re.search(r"4/[A-Za-z0-9_\-]+", clean)
    if m:
        return m.group(0).strip()

    # 3. If raw string with reasonable length and valid token characters
    stripped = re.sub(r"\s+", "", clean)
    if len(stripped) >= 15 and re.match(r"^[A-Za-z0-9_\-./+=]+$", stripped):
        return stripped

    return ""


# ─────────────────────────────────────────────────────────────────────────────
# 4. QR Code Engine
# ─────────────────────────────────────────────────────────────────────────────

def render_qr(data: str, invert: bool = True, border: int = 1) -> bool:
    """Display ASCII QR code in the terminal."""
    try:
        import qrcode
        qr = qrcode.QRCode(border=border)
        qr.add_data(data)
        qr.print_ascii(invert=invert)
        return True
    except ImportError:
        # Fallback to command-line qr if available
        if shutil.which("qr"):
            subprocess.run(["qr", data])
            return True
        sys.stderr.write("❌ python 'qrcode' package not installed. Run: pip install qrcode\n")
        return False
    except Exception as e:
        sys.stderr.write(f"❌ Failed to render QR: {e}\n")
        return False


# ─────────────────────────────────────────────────────────────────────────────
# 5. Network Discovery (LAN / Hotspot / Tailscale)
# ─────────────────────────────────────────────────────────────────────────────

def get_lan_ip() -> str:
    """Discover local reachable IP (Wi-Fi, hotspot gateway, or primary route)."""
    # 1. Try public UDP probe to find default route interface IP
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        if ip and not ip.startswith("127."):
            return ip
    except Exception:
        pass

    # 2. Check Android standard hotspot IP
    try:
        res = subprocess.run(["ifconfig"], capture_output=True, text=True, timeout=2)
        out = res.stdout or ""
        # Match wlan0 or ap0 or rndis0
        m = re.search(r"(?:wlan0|ap0|swlan0|rndis0)\s+.*?inet\s+([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)", out, re.DOTALL)
        if m:
            return m.group(1)
        # Any non-loopback inet
        all_inets = re.findall(r"inet\s+([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)", out)
        for cand in all_inets:
            if not cand.startswith("127."):
                return cand
    except Exception:
        pass

    return "127.0.0.1"


# ─────────────────────────────────────────────────────────────────────────────
# 6. AirLink Mobile Gateway (Web Server)
# ─────────────────────────────────────────────────────────────────────────────

class AirLinkGatewayHandler(http.server.BaseHTTPRequestHandler):
    target_url: str = ""
    command_name: str = "Command"
    on_code_callback = None

    def log_message(self, format, *args):
        # Quiet HTTP access logging
        pass

    def do_GET(self):
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
        if self.path == "/submit":
            length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(length).decode("utf-8", errors="ignore")
            params = urllib.parse.parse_qs(body)
            raw_input = params.get("code", [""])[0]
            clean_code = extract_auth_code(raw_input) or raw_input.strip()

            if clean_code and self.on_code_callback:
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
        self.server = None
        self.thread = None
        self.port = 8888
        self.lan_ip = get_lan_ip()

    def start(self):
        handler_cls = type(
            "CustomAirLinkHandler",
            (AirLinkGatewayHandler,),
            {
                "target_url": self.target_url,
                "command_name": self.command_name,
                "on_code_callback": self.on_code_received,
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
        return f"http://{self.lan_ip}:{self.port}"

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

    opts = parser.parse_args(argv)
    if not opts.args:
        parser.print_help()
        print("\nExamples:")
        print("  airlink agy                 Run agy with AirLink mobile auth gateway")
        print("  airlink --qr agy            Direct terminal QR code mode")
        print("  airlink ubu agy             Run on remote node 'ubu'")
        print("  airlink gh auth login       GitHub device flow across phones")
        return 0

    # Parse node vs command
    first = opts.args[0]
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
        cmd_tokens = opts.args[1:]
    else:
        cmd_tokens = opts.args

    cmd_str = " ".join(cmd_tokens)
    cmd_name = cmd_tokens[0] if cmd_tokens else "cli"

    print(f"\033[1;36m⚡ AirLink Launching:\033[0m \033[1m{cmd_str}\033[0m" + (f" (on @{target_node})" if is_remote else " (local)"))

    # Check initial token modification time for agy
    token_path = Path.home() / ".gemini" / "antigravity-cli" / "antigravity-oauth-token"
    token_mtime_before = token_path.stat().st_mtime if token_path.is_file() else 0

    # Prepare command execution
    if is_remote:
        exec_args = ["ssh", "-tt", target_node, f"cd ~ && {cmd_str}"]
    else:
        exec_args = cmd_tokens

    master_fd, slave_fd = pty.openpty()
    proc = subprocess.Popen(
        exec_args,
        stdin=slave_fd,
        stdout=slave_fd,
        stderr=slave_fd,
        close_fds=True,
    )
    os.close(slave_fd)

    buf = []
    lock = threading.Lock()
    url_captured = threading.Event()
    code_injected = threading.Event()
    gateway_server = None

    def deliver_code_to_proc(code: str):
        if code and not code_injected.is_set():
            code_injected.set()
            try:
                os.write(master_fd, (code.strip() + "\n").encode("utf-8"))
                sys.stdout.write(f"\n\033[1;32m✔ Code delivered to terminal!\033[0m\n")
                sys.stdout.flush()
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
            sys.stdout.write(f"\n\033[1;32m✔ Clean URL copied to clipboard!\033[0m\n")
            sys.stdout.flush()
            return

        if opts.open:
            sys.stdout.write(f"\n\033[1;32m✔ Opening URL on phone browser...\033[0m\n")
            sys.stdout.flush()
            if shutil.which("termux-open-url"):
                subprocess.Popen(["termux-open-url", clean], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            return

        if opts.qr:
            sys.stdout.write(f"\n\033[1;32m✔ Scan QR with Phone B to Authenticate:\033[0m\n")
            render_qr(clean, invert=True)
            sys.stdout.write(f"  \033[1;36m{clean}\033[0m\n")
            sys.stdout.write(f"\n\033[1;33m💡 When Phone B displays the code, paste it below:\033[0m\n")
            sys.stdout.flush()
            return

        # Default: Web Gateway Mode
        gateway_server = AirLinkServer(clean, cmd_name, deliver_code_to_proc)
        gateway_url = gateway_server.start()
        if gateway_url:
            set_clipboard(gateway_url)
            sys.stdout.write(f"\n\033[1;32m⚡ AirLink Gateway Active! Point Phone B camera at the QR code:\033[0m\n")
            render_qr(gateway_url, invert=True)
            sys.stdout.write(f"  \033[1;36mPortal Link:\033[0m \033[1m{gateway_url}\033[0m\n")
            sys.stdout.write(f"  \033[1;33m1. Scan with Phone B ➔ Tap Login ➔ Copy Code\033[0m\n")
            sys.stdout.write(f"  \033[1;33m2. Paste code into the web page to auto-deliver\033[0m\n\n")
            sys.stdout.flush()
        else:
            # Fallback to direct QR
            render_qr(clean, invert=True)

    # Output pump thread
    def output_pump():
        try:
            while True:
                r, _, _ = select.select([master_fd], [], [], 0.1)
                if master_fd in r:
                    data = os.read(master_fd, 1024)
                    if not data:
                        break
                    sys.stdout.buffer.write(data)
                    sys.stdout.flush()

                    text = data.decode("utf-8", errors="ignore")
                    with lock:
                        buf.append(text)
                    if not url_captured.is_set():
                        cand = extract_url_from_stream(text)
                        if cand:
                            on_url_found(cand)
                if proc.poll() is not None:
                    break
        except Exception:
            pass

    out_thread = threading.Thread(target=output_pump, daemon=True)
    out_thread.start()

    # Input relay thread
    def input_relay():
        try:
            while proc.poll() is None:
                r, _, _ = select.select([sys.stdin.fileno()], [], [], 0.2)
                if sys.stdin.fileno() in r:
                    line = sys.stdin.readline()
                    if not line:
                        break
                    try:
                        os.write(master_fd, line.encode("utf-8"))
                    except OSError:
                        break
        except Exception:
            pass

    in_thread = threading.Thread(target=input_relay, daemon=True)
    in_thread.start()

    # Background scanner on accumulated buffer in case URL was line-wrapped across reads
    deadline = time.time() + 45
    while time.time() < deadline and proc.poll() is None and not url_captured.is_set():
        with lock:
            all_text = "".join(buf)
        cand = extract_url_from_stream(all_text)
        if cand:
            on_url_found(cand)
            break
        time.sleep(0.3)

    rc = proc.wait()
    try:
        os.close(master_fd)
    except OSError:
        pass

    if gateway_server:
        gateway_server.stop()

    # Auto-save agy token if updated
    if not opts.no_save and ("agy" in cmd_tokens or "antigravity" in cmd_tokens):
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
        sys.exit(run_qr_cli(args[1:]))
    elif args and args[0] in ("code", "auth-code"):
        sys.exit(run_auth_code_cli(args[1:]))
    else:
        sys.exit(run_airlink(args))


if __name__ == "__main__":
    main()
