# SpotiFLAC Local — ARM64 build 165

Install `SpotiFLAC-Local-arm64-v8a.apk` over your previous SpotiFLAC Local installation. The original SpotiFLAC can remain installed.

- App: SpotiFLAC Local (`com.zarz.spotiflac.local`)
- Architecture: ARM64 only (`arm64-v8a`)
- Version: 5.1.1 / build 165 (split version code 2165)
- Minimum Android: 7.0 / API 24
- Source: `c4b79cee`
- Size: 54,328,531 bytes
- Icon: green logo on the same light cream background

Fixes Loved/playlist song rows disappearing when local cover artwork loads. The artwork
fade wrapper now honors the image size inside unconstrained list rows. The regression test
uses an actual local PNG, navigation into Loved and an empty-to-populated collection update.
Also includes all previous Local UI and offline cleanup changes.

The signing certificate matches build 164, allowing an update with existing Local app data retained.
Signature verification, ARM64 native backend packaging, 16 KB ELF/ZIP alignment and offline
permission checks passed for all 17 native libraries. Static analysis is clean;
1,609 Flutter tests passed with 3 skipped for this fix.
Physical-device installation/playback has not been tested here.

SHA-256: `bcaedfb169b3dec2f3d6e84485608f8c534926a6a0b449913ccf75b9b17a0bf0`

Sign into GitHub to download from this private repository.
