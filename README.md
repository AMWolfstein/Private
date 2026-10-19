# SpotiFLAC Local — ARM64 build 164

Install `SpotiFLAC-Local-arm64-v8a.apk` over your previous SpotiFLAC Local installation. The original SpotiFLAC can remain installed.

- App: SpotiFLAC Local (`com.zarz.spotiflac.local`)
- Architecture: ARM64 only (`arm64-v8a`)
- Version: 5.1.1 / build 164 (split version code 2164)
- Minimum Android: 7.0 / API 24
- Source: `1d29cf4f`
- Size: 54,328,531 bytes
- Icon: green logo on the same light cream background

Includes all changes since build 163: Wishlist removal, unified first-run guide,
Home/Library section cleanup, release-date ordering, Loved row visibility fix,
and removal of Local Library Default view and Audio quality preferences.

The signing certificate matches build 163, allowing an update with existing Local app data retained.
Signature verification, ARM64 native backend packaging, 16 KB ELF/ZIP alignment and offline
permission checks passed for all 17 native libraries. Static analysis is clean;
1,607 Flutter tests passed with 3 skipped before the build-number-only change.
Physical-device installation/playback has not been tested here.

SHA-256: `888ab03c7ad9487b7f6895dd8eb7e21e07b4fad6beca0d5bb409f585be165e15`

Sign into GitHub to download from this private repository.
