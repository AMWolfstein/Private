# Mornye Local v5.3.1 — ARM64 development-signed release APK

Download: [mornye-local-arm64-release.apk](./mornye-local-arm64-release.apk)

Android package: `com.zarz.mornye` (unchanged). Version code: 167.
Includes the preferred 60Hz window-mode controller and Release Performance Hub.
Monitoring/HUD default off. Original glass and playback source implementations were preserved.

This branch contains the APK artifact only, not the application source history.
Built from local changes on `mornye-reboot`, based on `0912a8e9`.
The feature source remains uncommitted because full-suite verification did not pass.

## Verification

- Release APK, ARM64-only: all 20 native libraries verified as ELF64 AArch64.
- Valid Android Debug v2 signature; ZIP alignment checked.
- Static analysis clean; 19 feature tests and 49 selected regression tests passed.
- Android unit tests: 177 passed, 2 skipped, no failures.
- Full Flutter suite failed/incomplete: 6204 passed, 25 skipped, 86 reported failures/errors.
- No connected device: installation, physical refresh rate and playback are not device-verified.
- 60Hz is a preference Android may override, not a physical refresh-rate guarantee.
- Proprietary Discord SDK absent: existing SDK-free fallback used.
- Different signing certificate prevents in-place update over an official build.

See `APK_DETAILS.json` for size, certificate fingerprint and build details.
Verify the downloaded APK using `sha256sum -c SHA256SUMS`.
