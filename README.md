# SpotiFLAC Local — ARM64 build 163

Install `SpotiFLAC-Local-arm64-v8a.apk` over the previous SpotiFLAC Local APK. The original SpotiFLAC can remain installed.

- App name: SpotiFLAC Local
- Package: com.zarz.spotiflac.local
- Architecture: arm64-v8a only
- Version: 5.1.1 (Flutter build 163; split version code 2163)
- Minimum Android: 7.0 (API 24)
- Source: 1474c860
- Size: 54,345,707 bytes
- Launcher: green logo on a light cream background

Includes the fragmented Opus metadata fix, local Home/artist/album/playlist designs,
Popular songs with dot paging, built-in-only playback, removed obsolete settings/conversion,
saved Normal/Immersive player views, and centered Loved / Play / Shuffle / Add to playlist actions.

The signing certificate matches the previous Local APK. App settings and library data are
retained during an update. A full local-library rescan is recommended to refresh metadata
using the newer Opus parser. No uninstall or format conversion is required.

The APK passed signature verification, 16 KB ZIP/ELF alignment checks, offline permission
checks, native backend packaging and ARM64-only checks (17 native libraries).
The app code passed 1,615 Flutter tests with 3 skipped before the icon/version-only update;
final static analysis is clean. Physical-device installation/playback remains untested here.

SHA-256: `bef4e5213fcb40cb529b809c4605a840a50cfcb05dd780a20cef39845410b83f`

Sign into GitHub to download from this private repository.
