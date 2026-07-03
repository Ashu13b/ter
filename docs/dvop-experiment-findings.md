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
