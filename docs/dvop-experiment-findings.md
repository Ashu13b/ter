# `dvop` Self-Grant Experiment — Findings

Branch: `feature/dvop-experiments`
Device: OnePlus 13R, OxygenOS 15 (Android 15)
Date: 2026-07-03

## Goal

Escape the `dvop off` self-lockout: after flipping
`development_settings_enabled=0`, Wireless Debugging shuts down and the
ADB channel dies. We wanted to flip it back **from Termux directly**,
without needing the phone-side menu-tap to re-enable Developer Options.

Approach tested: grant Termux the `WRITE_SECURE_SETTINGS` permission
once via ADB, then call `settings put global …` from within Termux
(uid 10509), no ADB required.

## Results — all three walls hit

### Wall 1: `pm grant` denied (even from ADB shell)

```
adb shell pm grant com.termux android.permission.WRITE_SECURE_SETTINGS
```

Fails with:

```
SecurityException: grantRuntimePermission: Neither user 2000 nor
current process has android.permission.GRANT_RUNTIME_PERMISSIONS.
```

On Android 15 / OxygenOS 15, shell UID (2000) has been stripped of the
`GRANT_RUNTIME_PERMISSIONS` privilege. Any recipe that says
"just run `pm grant …` once from ADB" — SetEdit, LADB, Shizuku setup
guides, most Tasker how-tos — is broken on this device.

`--user 0` and `appops set … WRITE_SECURE_SETTINGS allow` also fail
(the appops name doesn't exist; permissions ≠ appops).

### Wall 2: `settings` shell command needs `INTERACT_ACROSS_USERS`

`/system/bin/settings` on Android 15 is a one-line wrapper around
`cmd settings "$@"`. That `cmd` service always calls `getCurrentUser()`
before executing, which requires `INTERACT_ACROSS_USERS` (signature-
level, ungrantable to an app UID). From Termux directly:

```
$ settings put global development_settings_enabled 0
SecurityException: Permission Denial: getCurrentUser() from
uid=10509 requires android.permission.INTERACT_ACROSS_USERS
```

Passing `--user 0` explicitly hits `MANAGE_USERS` / `QUERY_USERS`
instead — same permission class, same wall.

Meaning: even if Wall 1 were bypassed and Termux held
`WRITE_SECURE_SETTINGS`, the shell `settings` binary itself would still
refuse to run under an app UID.

### Wall 3: `content` CLI blocked by SELinux (`app_process` inaccessible)

The older content-provider path — `content update --uri
content://settings/global --bind …` — bypasses the `getCurrentUser`
check because it doesn't have to. But:

```
$ /system/bin/content update --uri content://settings/global \
      --bind name:s:development_settings_enabled --bind value:i:0
/system/bin/content[3]: app_process: inaccessible or not found
```

`/system/bin/content` execs `app_process` (the Zygote/JVM bootstrapper).
On this device, `app_process` is not readable from Termux's
`untrusted_app` SELinux domain — `ls /system/bin/app_process*` returns
"no matches found" even though the binary exists on system.

`settings` on this build sneaks past that only because it now uses
`cmd`, which talks to `system_server` over binder instead of spawning
its own JVM.

## What actually still works

Only one path around all three walls remains:

**A custom Android APK** that calls `Settings.Global.putInt()` directly
via the Java API (`getContentResolver()`), *not* via the shell
`settings` wrapper. Java bypasses the `getCurrentUser` step because the
app already knows its own user context, and the APK's own manifest
declaration of `WRITE_SECURE_SETTINGS` is sufficient — no runtime
`pm grant` needed if the permission is declared at protection level
`signature|privileged|development` (which… it isn't for third-party
APKs, so we're back to Wall 1).

Wait: this is the trap. `WRITE_SECURE_SETTINGS` is `signature|
privileged`. A third-party APK declaring it in its manifest gets
**denied at install time** on Android 15 unless `pm grant` succeeds
during setup. And `pm grant` is Wall 1.

So even the "just build an APK" path is blocked on this device without
one of:

1. **Root** — `su -c pm grant …` bypasses Wall 1
2. **Shizuku running via `app_process`** (its bootstrap mechanism) —
   *might* still work here, untested. If Shizuku launches, other apps
   can call its binder to run privileged commands including `pm grant`.
3. **Waiting for a security update** to loosen the permission model
   (unlikely — the trend is tightening).

## Practical outcome for TER

Keep `dvop` on `main` as-is:
- The `on`/`off`/`toggle`/`status` toggle works fine while ADB is alive.
- `dvop off` triggers the confirm prompt that spells out the recovery
  ladder (phone-side Developer Options → Wireless Debugging → `adbcon`).
- `ter info` shows current dvop and ADB state.

Do **not** ship a custom APK or self-grant flow — the platform blocks
every viable path on OxygenOS 15. The 30-second menu-tap on the phone
is the leanest, least-attack-surface way to re-enable Developer
Options when needed.

Revisit if:
- OS update loosens the permission model, or
- Device is rooted (Magisk), or
- Shizuku ships a working bootstrap for OxygenOS 15 and we're willing
  to accept its persistent-privilege footprint.

## Post-reboot recovery — why the phone's own hotspot doesn't rescue you

After a reboot, `adb tcpip 5555` state is gone (runtime-only in adbd),
Wireless Debugging comes up **off** by default, and the 127.0.0.1:5555
loopback we locked last session is dead until the pair/connect dance
runs once more. That dance requires Wireless Debugging to be enabled,
which the platform gates on the phone being a Wi-Fi **client** (STA),
not an access point.

### Why "just use my own hotspot" fails

Single Wi-Fi radio; one role toward any given SSID:

- **STA** (client of someone else's AP)
- **SoftAP** (hosting a hotspot for others)
- **STA+AP concurrent** — chip can host *and* join, but the AP and STA
  are on **different networks**. The phone is never a client of the
  SSID it is itself broadcasting. No self-association, no DHCP lease
  from its own AP.

`AdbDebuggingManager` registers a `NetworkCallback` for
`TRANSPORT_WIFI` + `NET_CAPABILITY_INTERNET` and reads
`WifiManager.getConnectionInfo()`. In SoftAP-only mode that returns
null / `<unknown ssid>` — traffic rides an `ap0` / `swlan0` interface
that isn't `TRANSPORT_WIFI`. Callback never fires → Wireless Debugging
row stays greyed with "Connect to Wi-Fi to use".

Termux sitting on the hotspot LAN (`192.168.x.0/24`) can ping clients
fine — irrelevant. ADB checks the *phone's own STA state*, and there
isn't one.

Mobile data alone has the same problem: no `TRANSPORT_WIFI` network →
no ADB-over-Wi-Fi.

### Recovery paths, ranked

1. **Any real Wi-Fi both devices join** — home router, a friend's
   phone hotspot, portable travel router. Phone becomes STA → Wireless
   Debugging unlocks → `adbcon`.
2. **USB cable + laptop `adb`** — only fully-offline escape.
3. **STA+AP concurrent** — if you're already joined to a real upstream
   Wi-Fi you can *also* host a hotspot; ADB uses the STA side. Still
   needs one real AP to join.
4. **Keep a rescue AP handy when travelling** — cheap second phone or
   pocket router with a known SSID the phone auto-joins.

Nothing in TER can paper over this — it's a hardware constraint (one
radio, one role per SSID) dressed as a software gate. Documented here
so future-us doesn't waste an hour trying to make the phone talk ADB
to itself over its own hotspot.

### Faked-Wi-Fi workaround attempts

Short answer: no clean userspace workaround. Every "fake Wi-Fi" trick
either needs root or trips a different transport check.

**Things that look like they'd work but don't**

- **VPN / WireGuard tunnel** — ConnectivityManager reports these as
  `TRANSPORT_VPN`, not `TRANSPORT_WIFI`. `AdbDebuggingManager` filters
  for WIFI.
- **USB tethering from a laptop** (laptop shares its Wi-Fi to phone)
  — phone sees `TRANSPORT_ETHERNET` (rndis/ncm). Same filter miss.
- **Wi-Fi Direct (`p2p0` interface)** — separate `TRANSPORT_WIFI_AWARE`
  / p2p transport; `WifiManager.getConnectionInfo()` still returns null
  for the STA slot. Won't flip the toggle.
- **Termux hosting a hotspot itself** — you're still AP-side; nothing
  changed.

**Things that *do* work but aren't free**

- **Root + Magisk module / LSPosed hook** on
  `WifiManager.getConnectionInfo()` returning a fabricated `WifiInfo`
  with a plausible SSID + BSSID. `AdbDebuggingManager`'s callback then
  fires and the toggle unlocks. This is the real "fake Wi-Fi" answer
  — and it needs root, which this device doesn't have.
- **`svc wifi enable` + a phantom saved network** — no help without a
  real AP in range; the framework verifies association state, not just
  radio state.
- **Cheapest physical hack**: a $5 ESP32 or old phone flashed to
  broadcast a known SSID (`RESCUE-AP`) with no upstream. Phone
  auto-joins as STA, `WifiInfo` is real, Wireless Debugging unlocks.
  No internet needed — ADB only cares that STA is associated. This is
  the pragmatic "always-in-your-bag" fix.

**Why the framework is hard to spoof from userspace**

`WifiManager.getConnectionInfo()` and the `NetworkCallback` path read
from `WifiService` in `system_server` over binder. The state comes
from the kernel Wi-Fi HAL (`wpa_supplicant` → `nl80211` → driver). An
app UID can only *observe* it, not write it. Rewriting requires either:

- Signature-level `NETWORK_STACK` / `MANAGE_WIFI_*` permissions
  (ungrantable), or
- Hooking the binder response inside `system_server`'s process (root +
  Zygote injection).

Same class of wall as the `WRITE_SECURE_SETTINGS` problem — the
platform centralises the truth in `system_server` and only trusts
itself.
