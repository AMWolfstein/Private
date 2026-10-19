# SpotiFLAC Local — ARM64 build 166

Install `SpotiFLAC-Local-arm64-v8a.apk` over your previous SpotiFLAC Local installation. The original SpotiFLAC can remain installed.

- App: SpotiFLAC Local (`com.zarz.spotiflac.local`)
- Architecture: ARM64 only (`arm64-v8a`)
- Version: 5.1.1 / build 166 (split version code 2166)
- Minimum Android: 7.0 / API 24
- Source: `b62b3d9e`
- Size: 54,065,931 bytes
- Icon: green logo on the same light cream background

Moves Detailed logging to the first option in Logs and removes the empty App category.
Removes obsolete Embed lyrics settings and the Appearance Library preview card. Settings
and Library pages use the same circular back control as album pages. Includes the song
menus, local genre browser, Loved Songs label and artwork/number row changes since build 165.
Edit Metadata and Audio Quality Analysis remain available from song ellipsis menus.

The signing certificate matches build 165, allowing an update with existing Local app data retained.
Signature verification, ARM64 native backend packaging, 16 KB ELF/ZIP alignment and offline
permission checks passed for all 17 native libraries. Static analysis is clean;
1,590 Flutter tests passed with 3 skipped for this fix.
Physical-device installation/playback has not been tested here.

SHA-256: `5884f74494d15f06897b64461e193c286bfb492edb1a10607f4722aa42b363bd`

Sign into GitHub to download from this private repository.
