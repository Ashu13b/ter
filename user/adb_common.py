"""Shared ADB utility functions for TER tools."""
import subprocess


def get_adb_device():
    """Detect the best active ADB device serial."""
    try:
        proc = subprocess.run(
            ["adb", "devices"],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, timeout=5
        )
        devices = []
        for line in proc.stdout.splitlines()[1:]:
            if line.strip() and "device" in line and "unauthorized" not in line:
                parts = line.split()
                if parts:
                    devices.append(parts[0])
        if "127.0.0.1:5555" in devices:
            return "127.0.0.1:5555"
        for d in devices:
            if "emulator" in d:
                return d
        return devices[0] if devices else None
    except Exception:
        return None


def run_adb(args, device=None):
    """Run an ADB command, auto-detecting device if not provided. Returns (stdout, stderr, returncode)."""
    if device is None:
        device = get_adb_device()
    if not device:
        return "", "No active ADB device found", -1
    cmd = ["adb", "-s", device] + args
    try:
        proc = subprocess.run(
            cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, timeout=20
        )
        return proc.stdout.replace('\r', ''), proc.stderr.replace('\r', ''), proc.returncode
    except Exception as e:
        return "", str(e), -1
