# Phase 8 Android APK downloads

Download one APK and open it on your Android phone. Stay signed in to GitHub to access this repository.

- [ARM64 APK — most current phones](SpotiFLAC-offline-arm64.apk?raw=true)
- [ARMv7 APK — older 32-bit phones](SpotiFLAC-offline-armv7.apk?raw=true)
- [SHA-256 checksums](SHA256SUMS)

These are complete, independently installable APKs, not file chunks. Android 7.0/API 24 or newer is required.
Allow installation from your browser/file manager when Android prompts you.

Release-mode builds signed with the development key. They may not update an app signed with a different key; back up app data before replacing an existing installation. Physical-device playback is not yet tested.

Built from code commit `8609ad06092826c7ba3921b3231cbebd569a969f`; migration documentation is in commit `3933ae5` on main. Both APKs passed the Rust backend/ABI audit and signature verification. The release app has no Internet permission.

This branch contains build artifacts only. Application source and migration history remain on `main`.
