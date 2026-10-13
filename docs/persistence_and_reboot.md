# 📱 Android Optimization Persistence, Reboot & Developer Options Guide

This document clarifies how optimizations persist on Android, what happens across device reboots, and how Developer Options / Wireless Debugging affects system state.

---

## 1. Quick Summary Table: What Survives What?

| Optimization / Setting | Survives Reboot? | Survives Developer Options OFF? | How to Re-apply |
| :--- | :---: | :---: | :--- |
| **AOT Native Speed Compilation** (`cmd package compile -m speed-profile`) | **YES (Permanent)** | **YES** | Permanent on disk until app updates or OS upgrade |
| **Uninstalled Bloatware** (`pm uninstall --user 0`) | **YES (Permanent)** | **YES** | Permanent unless reinstalled via Play Store / APK |
| **Frozen / Disabled Apps** (`pm disable-user`) | **YES (Permanent)** | **YES** | Persists until explicitly run `app unfreeze` |
| **Global Settings (Phantom monitor toggle)** (`settings put global ...`) | **YES (Permanent)** | **YES** | Stored in Android system settings database |
| **Phantom Process Ceiling (2048)** (`device_config put activity_manager ...`) | **Partial (May reset)** | **YES** | Re-run `optimize fix` |
| **App Standby Buckets** (`am set-standby-bucket`) | **NO (Resets)** | **YES** | Re-run `optimize tier` |
| **Deviceidle / Doze Whitelist** (`dumpsys deviceidle whitelist +...`) | **NO (Resets)** | **YES** | Re-run `optimize fix` or `optimize tier` |
| **Wireless Debugging Port** | **NO (Randomized)** | **NO (Stops)** | Enable Wireless Debugging, run `adbcon` |

---

## 2. Does Turning Developer Options OFF Ruin the Optimizations?

**NO!** 

When you turn Developer Options **OFF**:
1. **Existing optimizations do NOT get deleted.** 
   - AOT compilation (`speed-profile`) compiles DEX bytecode into native AArch64 machine binaries saved directly to disk (`.oat`/`.odex`/`.art`). These files remain intact and execute at full native speed even with Developer Options off.
   - Global settings (`settings put global ...`) and frozen/uninstalled bloat remain untouched.
   - Active Standby buckets currently in RAM remain in their buckets until Android re-evaluates them.
2. **What Developer Options OFF actually does:**
   - It only turns off the **ADB bridge** (Wireless Debugging and USB Debugging).
   - Termux simply loses the ability to issue *new* ADB management commands while debugging is off.
3. **Safe Workflow:**
   - Turn Developer Options & Wireless Debugging **ON**.
   - Open Termux and run `adbcon`, followed by `optimize tier` and `optimize purge`.
   - Once completed, you can turn Developer Options **OFF** anytime. Your phone will continue to run with the optimizations in place!

---

## 3. What Happens When You Reboot Your Phone?

When you restart or power cycle your Android phone:
- **What remains in effect automatically:**
  - All apps that were compiled for speed (`Termux`, `WhatsApp`, `LiteRM`, `Chrome`, etc.) boot natively compiled without any slowdown.
  - All uninstalled bloat (Meta AI, 365, Wynk, JioCinema, Cisco Webex, etc.) stays uninstalled.
  - All frozen apps stay frozen (0% RAM/CPU).
- **What resets to Android defaults:**
  - Android reboots its internal `UsageStatsService`, which resets Standby Buckets to system defaults.
  - The runtime Doze battery whitelist clears.
  - The Wireless Debugging port changes (Android assigns a random port upon each boot).

---

## 4. Post-Reboot Routine (Under 60 Seconds)

Whenever you restart your phone, follow these quick steps to restore full background stability and deep-sleep tiering:

### Step 1: Turn on Wireless Debugging
1. Open Android **Settings** → **Developer Options**.
2. Toggle **Wireless Debugging** to **ON**. (Note the 5-digit port displayed, e.g. `42587`, or if paired on local loopback, it auto-connects).

### Step 2: Connect in Termux
Open Termux and run:
```bash
adbcon
```
*(If prompted or if port changed, run `adbcon <port>` e.g. `adbcon 42587`).*

### Step 3: Run One-Command Optimization
Apply phantom process limits, VIP speed-profile, and deep-sleep tiering in one go:
```bash
optimize fix && optimize tier
```

### Step 4: (Optional) Turn Off Developer Options
You can now toggle Developer Options / Wireless Debugging **OFF** in Android Settings. All applied policies will stay active in memory and on disk.

---

## 5. Verification Commands

To check the current state at any time:
```bash
optimize status             # One-liner status (WakeLock, Phantom limit, Battery exemption)
optimize info               # Live device health, battery %, temperature, and top CPU processes
optimize apps               # Standby bucket and whitelist status of all third-party apps
```
