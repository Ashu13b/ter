#!/usr/bin/env python3
"""
apk-audit.py - Deep Static Security, Privacy & Resource Efficiency Auditor for Android APKs
Analyzes permissions, cryptographic keys, embedded ad/tracker SDKs, native code,
and audits live memory footprint, swap cost, and background boot pressure.
"""

import sys
import os
import re
import subprocess
import zipfile
import hashlib

C_RESET = "\033[0m"
C_BOLD = "\033[1m"
C_RED = "\033[1;31m"
C_GREEN = "\033[1;32m"
C_YELLOW = "\033[1;33m"
C_BLUE = "\033[1;34m"
C_MAGENTA = "\033[1;35m"
C_CYAN = "\033[1;36m"
C_DIM = "\033[2m"

DANGEROUS_PERMISSIONS = {
    "android.permission.READ_SMS": ("SMS", "Can intercept 2FA codes & read personal messages"),
    "android.permission.RECEIVE_SMS": ("SMS", "Can trigger background listeners on incoming SMS"),
    "android.permission.SEND_SMS": ("SMS", "Can silently send premium rate SMS messages"),
    "android.permission.RECORD_AUDIO": ("Microphone", "Can eavesdrop and record audio in background"),
    "android.permission.CAMERA": ("Camera", "Can capture photos/video silently"),
    "android.permission.ACCESS_FINE_LOCATION": ("Location", "Real-time high-precision GPS tracking"),
    "android.permission.ACCESS_COARSE_LOCATION": ("Location", "Network-level location tracking"),
    "android.permission.READ_CONTACTS": ("Contacts", "Address book exfiltration"),
    "android.permission.WRITE_CONTACTS": ("Contacts", "Can tamper with saved contacts"),
    "android.permission.READ_CALL_LOG": ("Call Logs", "Can monitor call history"),
    "android.permission.READ_PHONE_STATE": ("Device ID", "Can harvest IMEI / SIM serial / phone number"),
    "android.permission.SYSTEM_ALERT_WINDOW": ("Overlay", "Can draw invisible overlays to hijack taps (clickjacking)"),
    "android.permission.REQUEST_INSTALL_PACKAGES": ("Dropper", "Can download and install rogue APKs silently"),
    "android.permission.WRITE_SETTINGS": ("System", "Can alter Android system settings (volume/brightness/toggles)"),
    "android.permission.BIND_ACCESSIBILITY_SERVICE": ("Accessibility", "Full screen scraper & keylogger capability")
}

KNOWN_TRACKERS = {
    "com.facebook.ads": ("Facebook Audience Network", "Advertising / Retargeting"),
    "com.facebook.appevents": ("Facebook App Events", "Behavioral & Conversion Analytics"),
    "com.google.android.gms.ads": ("Google AdMob", "Advertising & User Profiling"),
    "com.google.firebase.analytics": ("Firebase Analytics", "Cloud Event & Engagement Logging"),
    "com.google.firebase.crashlytics": ("Firebase Crashlytics", "Crash Logging & Stack Trace Diagnostics"),
    "com.appsflyer": ("AppsFlyer", "User Attribution & Install Fingerprinting"),
    "com.adjust.sdk": ("Adjust SDK", "Ad Attribution & Cross-App Tracking"),
    "com.branch": ("Branch.io", "Deep-Linking & Cross-Platform Attribution"),
    "com.onesignal": ("OneSignal", "Push Notification Telemetry & Engagement"),
    "com.amplitude": ("Amplitude", "Behavioral Analytics & User Tracking"),
    "io.sentry": ("Sentry", "Exception & Performance Telemetry"),
    "com.flurry": ("Flurry Analytics", "Mobile Behavioral Analytics"),
    "com.unity3d.services.ads": ("Unity Ads", "Mobile In-Game Video Ads"),
    "com.applovin": ("AppLovin", "Ad Monetization & Mediation Engine"),
    "com.ironsource": ("ironSource", "Ad Network & Monetization Platform"),
    "com.inmobi": ("InMobi", "Contextual & Location Ad Network")
}

def run_cmd(cmd):
    try:
        proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        return proc.stdout, proc.stderr, proc.returncode
    except Exception as e:
        return "", str(e), -1

def resolve_apk(query):
    # 1. Exact or relative file path
    if os.path.isfile(query):
        return os.path.abspath(query), False

    # 2. Check Downloads directory
    dl_paths = [
        os.path.expanduser("~/storage/downloads"),
        "/storage/emulated/0/Download",
        os.path.expanduser("~/Download")
    ]
    for d in dl_paths:
        if os.path.isdir(d):
            cand = os.path.join(d, query if query.endswith(".apk") else f"{query}.apk")
            if os.path.isfile(cand):
                return cand, False

    # 3. Check installed packages on device via ADB
    target_pkg = query
    out, _, code = run_cmd(["adb", "shell", "pm", "path", target_pkg])
    if code != 0 or "package:" not in out:
        # Try fuzzy match against installed packages
        pkgs_out, _, _ = run_cmd(["adb", "shell", "pm", "list", "packages"])
        matches = [p.replace("package:", "").strip() for p in pkgs_out.splitlines() if query.lower() in p.lower()]
        if matches:
            target_pkg = matches[0]
            out, _, code = run_cmd(["adb", "shell", "pm", "path", target_pkg])

    if code == 0 and "package:" in out:
        remote_path = out.splitlines()[0].replace("package:", "").strip()
        cache_dir = os.path.expanduser("~/.cache/ter-apk-audit")
        os.makedirs(cache_dir, exist_ok=True)
        local_apk = os.path.join(cache_dir, f"{target_pkg}.apk")
        print(f"📥 Pulling APK for installed package '{target_pkg}'...")
        run_cmd(["adb", "pull", remote_path, local_apk])
        if os.path.isfile(local_apk):
            return local_apk, True

    # 4. Search in downloads by fuzzy pattern
    for d in dl_paths:
        if os.path.isdir(d):
            for fname in os.listdir(d):
                if query.lower() in fname.lower() and fname.endswith(".apk"):
                    return os.path.join(d, fname), False

    return None, False

def audit_trackers_in_apk(apk_path):
    found_trackers = {}
    try:
        with zipfile.ZipFile(apk_path, 'r') as zf:
            for item in zf.namelist():
                if item.endswith(".dex") or "bundle" in item:
                    try:
                        content = zf.read(item)
                        for sig, (name, cat) in KNOWN_TRACKERS.items():
                            if sig.encode() in content:
                                found_trackers[sig] = (name, cat)
                    except Exception:
                        pass
    except Exception:
        pass
    return found_trackers

def audit_live_resource_footprint(pkg_name):
    # Check if app is installed and running
    out_mem, _, code = run_cmd(["adb", "shell", "dumpsys", "meminfo", pkg_name])
    if code != 0 or "No process found" in out_mem or "MEMINFO in pid" not in out_mem:
        # Check standby bucket & receivers even if not running
        b_out, _, _ = run_cmd(["adb", "shell", "am", "get-standby-bucket", pkg_name])
        bucket = b_out.strip()
        wl_out, _, _ = run_cmd(["adb", "shell", "dumpsys", "deviceidle", "whitelist"])
        is_wl = pkg_name in wl_out
        
        rx_out, _, _ = run_cmd(["adb", "shell", "dumpsys", "package", pkg_name])
        has_boot_receiver = "android.intent.action.BOOT_COMPLETED" in rx_out

        return {
            "running": False,
            "bucket": bucket,
            "whitelisted": is_wl,
            "boot_autostart": has_boot_receiver
        }

    # Process is running, parse memory numbers
    pss_mb = 0.0
    rss_mb = 0.0
    swap_mb = 0.0
    native_mb = 0.0
    dalvik_mb = 0.0

    for line in out_mem.splitlines():
        if "TOTAL PSS:" in line:
            parts = line.split()
            for idx, p in enumerate(parts):
                if p == "PSS:" and idx + 1 < len(parts):
                    try: pss_mb = float(parts[idx+1]) / 1024.0
                    except: pass
                elif p == "RSS:" and idx + 1 < len(parts):
                    try: rss_mb = float(parts[idx+1]) / 1024.0
                    except: pass
                elif p == "SWAP" and idx + 2 < len(parts):
                    try: swap_mb = float(parts[idx+2]) / 1024.0
                    except: pass
        elif "Native Heap" in line and not native_mb:
            parts = line.split()
            if len(parts) >= 2 and parts[2].isdigit():
                try: native_mb = float(parts[2]) / 1024.0
                except: pass
        elif "Dalvik Heap" in line and not dalvik_mb:
            parts = line.split()
            if len(parts) >= 2 and parts[2].isdigit():
                try: dalvik_mb = float(parts[2]) / 1024.0
                except: pass

    b_out, _, _ = run_cmd(["adb", "shell", "am", "get-standby-bucket", pkg_name])
    bucket = b_out.strip()
    wl_out, _, _ = run_cmd(["adb", "shell", "dumpsys", "deviceidle", "whitelist"])
    is_wl = pkg_name in wl_out
    rx_out, _, _ = run_cmd(["adb", "shell", "dumpsys", "package", pkg_name])
    has_boot_receiver = "android.intent.action.BOOT_COMPLETED" in rx_out

    return {
        "running": True,
        "pss_mb": pss_mb,
        "rss_mb": rss_mb,
        "swap_mb": swap_mb,
        "native_mb": native_mb,
        "dalvik_mb": dalvik_mb,
        "bucket": bucket,
        "whitelisted": is_wl,
        "boot_autostart": has_boot_receiver
    }

def audit_apk(apk_path):
    print("\n" + C_MAGENTA + "┌────────────────────────────────────────────────────────────────────────┐" + C_RESET)
    print(C_MAGENTA + "│" + C_RESET + "              🛡️  " + C_BOLD + "TER OS: DEEP APK SECURITY & EFFICIENCY AUDITOR" + C_RESET + "        " + C_MAGENTA + "│" + C_RESET)
    print(C_MAGENTA + "└────────────────────────────────────────────────────────────────────────┘" + C_RESET)
    print(f"Target: {C_BOLD}{apk_path}{C_RESET}")

    # File Hashes
    size_mb = os.path.getsize(apk_path) / (1024 * 1024)
    with open(apk_path, "rb") as f:
        data = f.read()
        sha256 = hashlib.sha256(data).hexdigest()
    print(f"Size  : {size_mb:.2f} MB")
    print(f"SHA256: {C_DIM}{sha256}{C_RESET}")

    # 1. Manifest / Badging via aapt
    out_b, _, _ = run_cmd(["aapt", "dump", "badging", apk_path])
    pkg_name = "Unknown"
    version_name = "?"
    target_sdk = "?"
    app_label = "Unknown"

    for line in out_b.splitlines():
        if line.startswith("package:"):
            m = re.search(r"name='([^']+)'", line)
            if m: pkg_name = m.group(1)
            m_v = re.search(r"versionName='([^']+)'", line)
            if m_v: version_name = m_v.group(1)
        elif line.startswith("application-label:"):
            m = re.search(r"'([^']+)'", line)
            if m: app_label = m.group(1)
        elif line.startswith("targetSdkVersion:"):
            m = re.search(r"'([^']+)'", line)
            if m: target_sdk = m.group(1)

    print(f"\n{C_BOLD}📦 Identity:{C_RESET}")
    print(f"  • Name        : {C_CYAN}{app_label}{C_RESET} ({pkg_name})")
    print(f"  • Version     : {version_name} (Target SDK: {target_sdk})")

    # 2. Signature & Certificate Audit
    out_sig, _, _ = run_cmd(["apksigner", "verify", "--verbose", "--print-certs", apk_path])
    is_debug_cert = False
    is_test_key = False
    cert_subj = "Unknown"

    for line in out_sig.splitlines():
        if "certificate DN:" in line:
            cert_subj = line.split("certificate DN:")[1].strip()
            if "Android Debug" in cert_subj or "android@android.com" in cert_subj:
                is_debug_cert = True
            if "testkey" in cert_subj.lower():
                is_test_key = True

    print(f"\n{C_BOLD}🔑 Signature & Integrity:{C_RESET}")
    if is_debug_cert or is_test_key:
        print(f"  • Certificate : {C_RED}⚠️  DEBUG / AOSP TEST KEY DETECTED!{C_RESET}")
        print(f"    ↳ {C_YELLOW}Signer: {cert_subj}{C_RESET}")
        print(f"    ↳ {C_RED}Verdict: Unofficial / Modded build (Not signed by official publisher).{C_RESET}")
    else:
        print(f"  • Certificate : {C_GREEN}Signed with release certificate{C_RESET}")
        print(f"    ↳ Signer: {cert_subj[:60]}...")

    # 3. Permissions Analysis
    perms = re.findall(r"uses-permission: name='([^']+)'", out_b)
    flagged_perms = []
    normal_perms = []

    for p in perms:
        if p in DANGEROUS_PERMISSIONS:
            flagged_perms.append((p, DANGEROUS_PERMISSIONS[p]))
        else:
            normal_perms.append(p)

    print(f"\n{C_BOLD}🚨 Permissions Audit ({len(perms)} total requested):{C_RESET}")
    if flagged_perms:
        print(f"  {C_RED}High-Risk / Sensitive Permissions ({len(flagged_perms)}):{C_RESET}")
        for p, (cat, desc) in flagged_perms:
            print(f"    • {C_RED}{p}{C_RESET} [{C_YELLOW}{cat}{C_RESET}]")
            print(f"      ↳ {desc}")
    else:
        print(f"  {C_GREEN}✔ No high-risk dangerous permissions requested.{C_RESET}")

    if normal_perms:
        print(f"\n  {C_DIM}Standard Permissions ({len(normal_perms)}):{C_RESET}")
        for p in normal_perms[:4]:
            print(f"    • {C_DIM}{p}{C_RESET}")
        if len(normal_perms) > 4:
            print(f"    • {C_DIM}...and {len(normal_perms) - 4} more.{C_RESET}")

    # 4. Embedded Ad & Analytics Trackers Audit
    trackers = audit_trackers_in_apk(apk_path)
    print(f"\n{C_BOLD}📡 Embedded Tracking & Telemetry SDKs:{C_RESET}")
    if trackers:
        print(f"  {C_YELLOW}Detected {len(trackers)} third-party telemetry / advertising libraries:{C_RESET}")
        for sig, (name, cat) in trackers.items():
            print(f"    • {C_YELLOW}{name:<30}{C_RESET} [{cat}]")
    else:
        print(f"  {C_GREEN}✔ No commercial ad or attribution tracking SDKs detected.{C_RESET}")

    # 5. Framework & Native Code Inspection
    framework = "Native Android (Java/Kotlin)"
    native_libs = []
    try:
        with zipfile.ZipFile(apk_path, 'r') as zf:
            namelist = zf.namelist()
            if any("libreactnative" in n for n in namelist):
                framework = "React Native (Hermes Engine)"
            elif any("libflutter.so" in n for n in namelist):
                framework = "Flutter"
            elif any("libunity.so" in n for n in namelist):
                framework = "Unity Engine"
            elif any("libmonosgen" in n for n in namelist):
                framework = "Xamarin / .NET"

            for n in namelist:
                if n.startswith("lib/arm64-v8a/") and n.endswith(".so"):
                    native_libs.append(os.path.basename(n))
    except Exception:
        pass

    print(f"\n{C_BOLD}⚙️  Framework & Engine:{C_RESET}")
    print(f"  • Runtime Engine    : {C_CYAN}{framework}{C_RESET}")
    if native_libs:
        print(f"  • Native Binaries   : {', '.join(native_libs[:5])}{'...' if len(native_libs) > 5 else ''}")

    # 6. Live Resource & RAM Advisor
    res = audit_live_resource_footprint(pkg_name)
    print(f"\n{C_BOLD}💾 Resource & Memory Efficiency Advisor:{C_RESET}")
    if res.get("running"):
        pss = res.get("pss_mb", 0)
        rss = res.get("rss_mb", 0)
        swap = res.get("swap_mb", 0)
        color = C_GREEN if pss < 150 else (C_YELLOW if pss < 350 else C_RED)
        print(f"  • Process State     : {C_GREEN}Currently Active / Cached in RAM{C_RESET}")
        print(f"  • Physical RAM (PSS): {color}~{pss:.1f} MB{C_RESET} (RSS: ~{rss:.1f} MB)")
        if swap > 0:
            print(f"  • Swapped Out (ZRAM): {C_YELLOW}~{swap:.1f} MB{C_RESET}")
        if res.get("native_mb") or res.get("dalvik_mb"):
            print(f"  • Heap Breakdown    : Native C++ ~{res.get('native_mb', 0):.1f} MB | Java Dalvik ~{res.get('dalvik_mb', 0):.1f} MB")
    else:
        print(f"  • Process State     : {C_DIM}Not currently in RAM (Idle){C_RESET}")

    bucket_val = res.get("bucket", "unknown")
    b_color = C_GREEN if bucket_val in ["5", "10", "active"] else (C_RED if bucket_val in ["45", "restricted"] else C_YELLOW)
    print(f"  • Standby Bucket    : {b_color}Bucket {bucket_val}{C_RESET}")
    if res.get("boot_autostart"):
        print(f"  • Boot Auto-Start   : {C_YELLOW}⚠️  Registers BOOT_COMPLETED (Starts automatically on phone reboot){C_RESET}")
    else:
        print(f"  • Boot Auto-Start   : {C_GREEN}✔ No boot-start receiver{C_RESET}")

    # 7. Actionable Recommendation
    print(f"\n{C_BOLD}💡 Efficiency & Action Recommendation:{C_RESET}")
    if pkg_name in ["com.termux", "com.whatsapp", "dev.expeei.literm", "org.kaggle.platform", "org.telegram.messenger"]:
        print(f"  • Recommendation    : {C_GREEN}KEEP UNRESTRICTED (Protected Essential Tool){C_RESET}")
        print(f"    ↳ Already exempted from Doze & Standby limits to ensure fast execution.")
    elif res.get("running") and res.get("pss_mb", 0) > 250:
        print(f"  • Recommendation    : {C_YELLOW}RESTRICT TO DEEP SLEEP ('optimize restrict {pkg_name}'){C_RESET}")
        print(f"    ↳ App holds ~{res.get('pss_mb', 0):.1f} MB of RAM. Restricting it allows instant launch when opened, but prevents it from running when idle.")
    elif is_debug_cert or is_test_key:
        print(f"  • Recommendation    : {C_YELLOW}MODDED BUILD CAUTION{C_RESET}")
        print(f"    ↳ Untrusted signer key. Safe to keep if intentional, but restrict background access: 'optimize restrict {pkg_name}'")
    else:
        print(f"  • Recommendation    : {C_GREEN}BALANCED / NORMAL{C_RESET}")
        print(f"    ↳ App behaves within expected bounds.")

    print(C_MAGENTA + "\n────────────────────────────────────────────────────────────────────────" + C_RESET + "\n")

def main():
    if len(sys.argv) < 2 or sys.argv[1] in ["-h", "--help"]:
        print("\033[1;36mTER OS: APK SECURITY, PRIVACY & RESOURCE AUDITOR\033[0m")
        print("Usage: apk-audit <file.apk | package_name | search_query>")
        print()
        print("Examples:")
        print("  app audit whatsapp")
        print("  app audit myapp.apk")
        print("  app audit com.dubox.drive")
        print()
        sys.exit(0)

    target = sys.argv[1]
    apk_file, is_pulled = resolve_apk(target)
    if not apk_file:
        print(f"{C_RED}❌ Could not find APK or installed package matching '{target}'.{C_RESET}")
        sys.exit(1)

    audit_apk(apk_file)

if __name__ == '__main__':
    main()
