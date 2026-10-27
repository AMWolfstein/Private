# Sistrum — local Android player

This fork is an offline music player for Android. It plays music already on your device;
there are no online providers, extensions, downloads, network drives or accounts.
The app uses Mornye with light/dark modes, accent colors and local custom fonts.

Features include local library scanning and search, albums/artists/playlists, queues,
embedded and sidecar lyrics, metadata and artwork editing, ReplayGain normalization,
automix, listening statistics, local profiles, backup/restore, SAF storage and USB audio.
The release app does not request Internet access. External project links open in your browser.
Android 7.0 (API 24) or newer is required; USB/DAP features depend on device support.

## Install

Open the APK on your phone and allow installation from the browser or file manager when
Android asks. A locally built APK uses the development signing key unless release signing
is configured; it may not update an installation signed by a different key. Back up app data
before replacing such an installation.

The app ID is `com.amwolfstein.sistrum` (`com.amwolfstein.sistrum.local` for
Sistrum Local). The retired Sistrum Compose app uses the same base ID: uninstall
it before installing this app. This is a separate installation from SpotiFLAC;
export a backup in the old player and restore it in Sistrum. Old backup formats
and persisted settings remain compatible; folder permissions must be granted again.

After setup, select a local music folder, grant access, scan it and choose a track.
For removable storage, use Android's folder picker and retain its storage permission.
See [player widgets](docs/player_widgets.md) for launcher controls.

## Develop and build

Use Flutter 3.47.7 (the version in `.fvmrc`), the Rust toolchain in
`rust_backend/rust-toolchain.toml`, Java 25 and the Android SDK/NDK/CMake versions pinned
in `android/app/build.gradle.kts`. Install Clang/libclang for binding generation.
In the prepared cloud workspace, run `source /workspace/toolchains/activate.sh` per shell.

```bash
flutter pub get
flutter analyze
flutter test
bash scripts/check_rust_backend.sh
bash scripts/build_rust_backend.sh android
flutter build apk --release --target-platform android-arm,android-arm64
```

The APK is written to `build/app/outputs/flutter-apk/`. Use
`scripts/check_backend_apk.py <apk> --backend rust --abis arm64-v8a,armeabi-v7a`
to audit a universal build. Physical-device playback, SAF, USB and widget checks are
separate from host tests.

Branding uses the owner's transparent `logo/logo.png` without recolouring. With
Python/Pillow available, run `python3 scripts/generate_sistrum_branding.py`, then
`dart run flutter_launcher_icons` to regenerate icon inputs, the notification
silhouette and launcher outputs. Android adds its own launcher/splash masks; the
flat dark ground is not the textured rounded-square artwork in `logo/logo2.png`.

The Rust workspace contains `core`, `local`, `mobile` and `bindgen`. Local file operations
cross generated UniFFI Kotlin bindings; audio playback remains native Android.
See [CONTRIBUTING.md](CONTRIBUTING.md), [AGENTS.md](AGENTS.md), and
[the migration tracker](LOCAL_OFFLINE_MIGRATION_PLAN.md) for workflow and validation status.

## Credits and license

Based on [SpotiFLAC Mobile](https://github.com/spotiflacapp/SpotiFLAC-Mobile) by Zarz Eleutherius
and [SpotiFLAC](https://github.com/afkarxyz/SpotiFLAC) by afkarxyz, with contributions credited
in the app. Existing license terms and third-party license notices remain in place.
