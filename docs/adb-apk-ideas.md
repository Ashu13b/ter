# adb-apk Wrapper — Future Feature Ideas

## Why
Raw `adb install` works but gives cryptic errors and lacks convenience features.

## Planned Improvements

1. **ADB connection check** — detect if ADB is connected, prompt "Run adbcon first" if not
2. **Fuzzy-find APKs** — auto-search `~/storage/downloads/` so user doesn't need full path
3. **Show app info before install** — extract package name & version from APK using `aapt`
4. **Batch install** — support `adb-apk *.apk` for multiple APKs at once
5. **Split APK / XAPK support** — auto-detect and use `install-multiple` for bundles
6. **Friendly error messages** — translate `INSTALL_FAILED_UPDATE_INCOMPATIBLE` → "Signature mismatch — uninstall first?"
7. **Optional app launch** — ask to open the app after install

## Location
- Shell wrapper: `user/adb_utils.sh`
- Would use `_get_adb_device()` helper already in place
