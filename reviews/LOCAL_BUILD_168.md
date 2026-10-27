# Local ARM64 release 168

> Identity normalization (T16, 2026-10-28): historical names, paths and command strings below were mechanically renamed. Original evidence used the former terms; no listed checks were rerun by this rename. Encoded upstream/download identifiers retain their actual destinations.

Fetched branch `ccr-2fb644cd-nmesyt` through `d4dff781` (glass-clarity slider jank fix).
Only release version fields changed afterward: source `2a2ab3be` sets pubspec/AppInfo build
168; graph checkpoint `686a463f`. No audit bug fixes were applied.

- App: Sistrum Local, `com.amwolfstein.sistrum.local`, version 5.1.1 / build 168.
- Split APK versionCode: 2168; minimum API 24 / target API 37; ARM64 only.
- Artifact: `Sistrum-Local-168-arm64-v8a.apk`, 52,787,208 bytes.
- SHA-256: `98c0ab17ef57b39870e24b654a1ad6be8883d7d09923a9a61c6ee5a2032cdecf`.
- Certificate SHA-256: `b912cdc7e97b78a19aff3ac8398abc3b36251de2af67243e8a6da2870e15c7b3`, matches Local build 167.
- Release backend/ZIP CRC audit, embedded source revision, 17 AArch64 native libraries,
  ELF/ZIP 16KB alignment, cream adaptive icon and no INTERNET permission: PASS.
- Analysis: PASS, no issues on the final versioned source.
- Full Flutter suite on fetched source: PASS, `03:46 +1514 ~3: All tests passed!`.
  Changes since that run are only the two release version fields and generated graph/docs;
  the release compilation and artifact checks passed with build 168.
- Device installation, smoothness, storage/audio runtime: NOT RUN.

Build command (after sourcing `/workspace/toolchains/activate.sh`):

```sh
SISTRUM_SIDE_BY_SIDE=true SISTRUM_RUST_ANDROID_ABIS=arm64-v8a flutter build apk --release --target-platform android-arm64 --split-per-abi --obfuscate --split-debug-info=build/symbols/android --dart-define=GIT_COMMIT=2a2ab3be --build-number=168
```

Build finished in 165.2 seconds. Logs: `/workspace/local-168-*.log`;
artifact facts: `/workspace/local-168-apk-details.json`.

Published artifact-only branch `apk-local-arm64-168`, commit `632c07a844bd9ebbe0e70f9310523cdaf52d2b2c`;
remote SHA verified after push. Contains APK, README, SHA256SUMS and APK_DETAILS.json.
[Download APK](https://github.com/AMWolfstein/Private/raw/refs/heads/apk-local-arm64-168/%53%70%6F%74%69%46%4C%41%43-Local-168-arm64-v8a.apk).

Audit work was paused at the owner's request. Its untracked folder
`reviews/audit-2026-10-21/` is preserved separately, excluded from this release checkpoint
and Graphify refresh. Its reproduction Dart file is kept as a `.dart.txt` attachment so it
is not mistaken for production source by Flutter analysis. No audit completion is claimed.
