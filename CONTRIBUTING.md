# Contributing

This repository targets a local, offline Android music player. Read `AGENTS.md` and
`LOCAL_OFFLINE_MIGRATION_PLAN.md` before editing. Keep local playback, SAF permissions,
backup/restore and USB behavior intact; do not reintroduce online providers or downloads.

Use Flutter 3.47.7, the pinned Rust toolchain, Java 25 and the Android SDK/NDK/CMake versions
in `android/app/build.gradle.kts`. In the prepared cloud workspace, source
`/workspace/toolchains/activate.sh`. Run `flutter pub get` after dependency edits. Regenerate
JSON models with `dart run build_runner build` and translations with `flutter gen-l10n`.
Keep localizations in `lib/l10n/arb/`; generated translation Dart files are ignored. New offline
wording currently falls back to English where updated translations are missing. Translate the
new meaning rather than restoring obsolete online guidance.

Before removing a feature, query the Graphify map and trace its callers. After edits run:

```bash
flutter analyze
flutter test
bash scripts/check_rust_backend.sh
python3 -m unittest discover -s scripts -p 'test_*.py'
bash scripts/build_rust_backend.sh android
flutter build apk --release --target-platform android-arm,android-arm64
```

Also compile Android instrumentation tests when native bridges change. Host tests do not
replace device tests for storage permissions, audio routing, USB, statx compatibility,
background playback and launcher widgets. Never change vendored native libraries casually.

Commit source/tests/config first. Run `graphify update .` (AST-only) and commit tracked
`graphify-out/` files separately. Finally commit progress and documentation. Stage explicit
paths; do not add generated caches, build output, signing keys or APKs to Git.
