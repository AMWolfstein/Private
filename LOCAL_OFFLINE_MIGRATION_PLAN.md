# Local / Offline / Android-only Migration Plan

Goal: convert `spotiflac_android` from an **extension-driven online downloader** into a
**local, offline, Android-only music player**.

Chosen scope (confirmed):
- Rust backend: keep local parts, strip online.
- Remove: extensions + providers + download engine, network storage (SMB/WebDAV),
  non-Android platforms, online UI surfaces, Discord presence.
- Approach: plan doc, then phased commits (one reviewable commit per subsystem).

Verification for every phase: `flutter analyze`, `bash scripts/check_rust_backend.sh`
(cargo fmt/clippy/test), `bash scripts/build_rust_backend.sh android`, then
`flutter build apk`; run `graphify update .` after code changes.
**Current user instruction (2026-10-18): complete Phase 8, then build an APK.** This
supersedes the earlier Phase 7 instruction to stop APK builds.

---

## Progress

_Last updated: 2026-10-18_

**Status:** Phases 1-8 implemented and committed. Host validation and the release APK
build/audit passed. Physical-device validation remains pending.
Vision refinements V1-V4 captured; Phase 6 decisions recorded in `PHASE6_DECISIONS.md`.

**Committed:**
- `f0a1b45` — graphify baseline (graph + report).
- `159a9c2` — Phase 1: removed `ios/`, `third_party/discord/`, online release tooling/docs/scripts;
  trimmed `analysis_options.yaml` platform excludes.
- `91240e2` — Phase 2: Discord rich presence removed (Dart settings/model/l10n, widget, gradle,
  AndroidManifest, build/audit scripts + tests, ios/discord scripts).
- `b038493` — docs: migration plan + progress tracker.
- `757ebcc` — Phase 3: updater / remote-config / announcements / donations removed
  (services, dialogs, upgrade-intro screen, donate page, settings keys + UI, install permission,
  APK FileProvider, tests).
- Phase 4 (this commit) — network storage (SMB/WebDAV/NAS) full rip-out: 10
  `lib/services/network_*.dart`, `network_storage_screen.dart`, `network://` URI scheme +
  branches (player service/runtime, playback, hires check, audio analysis, file access),
  `networkDownloadFolder/Label` settings (model/generated/provider/codec/UI), l10n keys (en/id),
  `dart_smb2` dep + `libsmb2.txt` license, and all `network_*` tests + 2 Python SMB fixtures.
- `05bf2fe` — Phase 5a: extension store / repo tab / provider-priority settings removed
  (`RepoTab`/`repoProvider`, extension store + detail + repo card/row widgets, extensions /
  download-fallback-extensions / lyrics+metadata+provider priority / profile-priority-list
  settings pages, `showExtensionStore` setting, settings-search + download/lyrics/metadata rows);
  `main_shell`/`ShellTab` renumbered without the repository tab. **Kept** the local profile
  feature (`ProfileSettingsPage` + settings profile card) and the extension *registry* +
  `ExtensionStorageService` (keep until the download engine goes in Phase 6).
- `0567a80` — Phase 5b: online metadata autofill, batch re-enrich, local-track redownload,
  cross-extension share, open-on-platform, hi-res check, audio preview removed
  (services/widgets/providers + track-metadata, queue/library, download picker, `main_shell`
  preview observers). Downloads now resolve the default service directly. **Deferred to Phase 6**
  (removed with the download engine): the extension *registry* (`extension_provider`),
  `track_provider` + Mornye home search, and motion artwork.
- `83a02c4` — Phase 5c: explore home feed, weekly releases, artist concerts, motion artwork
  removed (`explore_provider` + featured section + `home_tab_explore` part; weekly-releases
  provider/service/screen; artist-concerts screens/button/model; motion-artwork download/proxy/
  store + motion header banner + player artwork video/motion providers + download motion source;
  `track_provider.artistConcerts`; motion-artwork rendering in now-playing / mini-player / album
  screens / cache management; motion+home-feed settings). Home tab keeps local recent/import
  sections and home search. Phase 5 complete.
- `f3ab83e` — Phase 6: download engine removed and player/queue re-pointed to the local library
  (D1). Deleted all `download_queue_provider*`/`download_queue_state`/
  `download_verification_retry_guard`, `download_history_provider*` (state moved to
  `models/download_history.dart`), `extension_provider*`, `track_provider`,
  `models/download_item(.g)`/`download_result`/`extension`; all `services/download_*`,
  `native_download_history`, `verification_notification`, `cover_download_service`,
  `album_replaygain_readiness`, `extension_storage_service`; `utils/download_error_type`/
  `extension_*`; screens `downloaded_album_screen`/`home_tab_import`/`album_screen`/`artist_screen`/
  `artist_screen_widgets`/`playlist_screen`; widgets `downloadable_cover`/`download_queue_feedback`;
  `settings/download_settings_page`; and the Android `DownloadService*`/`NativeDownloadFinalizer*`/
  `NativeFinalizationPolicy*`/`SafDownloadHandler.kt`/`DownloadQueueWidgetProvider.kt` + widget
  resources (added `SafFileOps.kt`). Re-pointed `music_player_provider`/`playback_provider`/
  `library_search_provider`/`library_browse_provider`/`queue_tab*`/`home_tab*`/`main_shell`/settings
  to the local library DB; purged all download/extension settings keys (kept `downloadDirectory`/
  `downloadDirectoryBookmark`/`storageMode`/`downloadTreeUri`). Per PD2 the Dart SQL layer is
  local-only but `history.db` stays ATTACHed (native-scan exclusion SQL + Rust refs re-homed in
  Phase 7). ~62 offline tests deleted, ~38 edited.
- `dfd7f43` — graphify: refreshed code graph after Phase 6 (57360 → 26443 nodes: deleted code plus
  generated `app_localizations*.dart` now ignored).

**Phase 5 summary:** the entire online extension/provider/search UI layer is gone; what remains
online-coupled (`extension_provider` registry, `track_provider`, Mornye home search) is consumed
only by the download engine and is removed with it in Phase 6. Two now-dead settings
(`homeFeedProvider`, explore-feed cache row) are deferred to the Phase 8 settings purge (V4).

**Phase 6 summary (historical; Phase 7 changes below supersede the native/history details):** the app is now a local-only player in Dart. The download engine, extension
registry, `track_provider`, Mornye home search and all download/verification UI are gone; the
player, queue and search read the local library DB. Per PD2 the Dart SQL layer no longer queries the
download history, but `history.db` remains ATTACHed and the native library scan still excludes it —
both re-homed to Rust in Phase 7. Two kept-but-dormant pieces (`downloaded_embedded_cover_resolver`,
the `history.db` attach) are slated for Phases 7-8. `flutter analyze` repo-wide is clean; full
`flutter test` passes (only the known-flaky perf test).

**Phase 7 implementation:**
- `a9f63b9` pruned core online-support modules; `fa2afff` completed the reduction.
- `7d54453` refreshed the graph from code commit `fa2afff0`.
- New `spotiflac-local` crate owns local scans, CUE handling, metadata/tag writes, artwork,
  lyrics and logging. Scoped file grants, cancellation, atomic file publication and shutdown
  draining remain; shutdown is idempotent and waits for active operations.
- Removed `providers`, `network` and `extensions`; workspace now contains `core`, `local`,
  `mobile` and `bindgen`. Removed 126 lockfile packages without upgrading retained packages.
  Kept vendored rustix/libusb sources unchanged.
- Replaced `ExtensionManager` with automatically initialized `LocalBackend`; removed native
  provider/auth/repository/download APIs and extension event dispatch. Local embedded/sidecar
  lyrics reading, editing and export remain, with no online fallback. Legacy request fields
  remain temporarily for caller compatibility.
- Native and Dart library imports no longer attach/filter against `history.db`.
- Build scripts generate Kotlin bindings only; removed iOS/Swift/podspec/staticlib wiring and
  moved the statx example to the local crate. The native FFmpeg command queue was used only by
  extensions and was removed; local Dart FFmpeg conversion/tag fallback remains.
- Updated Android callers and integration fixtures; removed obsolete extension/download tests.
  Replaced deleted SAF helper references and stale Phase 6 manifest service/widget entries;
  removed retired provider deep links. INTERNET/localhost policy stays pending the Phase 8 audit.

**Phase 7 validation:**
- `flutter analyze`: **No issues found**.
- Full `flutter test`: **1645 passed, 3 skipped**; paging performance test passed this run.
- `bash scripts/check_rust_backend.sh`: fmt/clippy clean; **215 passed, 1 existing ignored**.
- Python script tests: **12 passed**.
- `:app:compileDebugKotlin` and `:app:compileDebugAndroidTestKotlin` passed without APK
  packaging. `:app:testDebugUnitTest`: **63 passed, none skipped**, including six native
  data-job ABI/cancellation tests using the host Rust library. Fixed the fixture FFmpeg imports
  and removed a leftover test of the download-finalizer helper deleted in Phase 6.
- Host and Android ARM64/ARMv7 Rust builds passed. Checked 16 KB ELF segment alignment and
  absence of retired extension/repository exports.
- Kotlin-to-Rust host ABI smoke passed: local metadata, grant revocation, local lyrics/export,
  shutdown, native data jobs and cancellation.
- At the end of Phase 7, APK validation was **incomplete**: a stale Phase 6 widget manifest
  reference was fixed, then release CMake dependency population failed. The user stopped APK
  builds for Phase 7 and subsequently authorized a Phase 8 APK build; see the results below.
- No Android device or emulator is available; app playback, SAF/USB, statx and on-device
  integration tests have not run.
- Graphify was queried before removal and refreshed afterward (AST-only): **23223 nodes,
  44926 edges, 639 communities**. No nodes are attributed to the three deleted crates.
  Eight extractor syntax warnings are confined to unchanged vendored C/libusb sources.

**Phase 8 implementation:**
- `8609ad06` — final local-player cleanup; `929792e1` refreshed Graphify from that code commit. Removed direct dependencies on `http`,
  `connectivity_plus`, `cached_network_image`, `flutter_cache_manager`,
  `flutter_secure_storage`, `receive_sharing_intent`, `video_player`, `dynamic_color` and
  the video-player test interface; removed 19 resolved packages and regenerated the lockfile
  without upgrading retained packages.
  Kept archive/crypto for local backups and hashing, XML/HTML for local parsing, and
  url_launcher for explicit external browser links. Shared widget libraries remain in use.
- Removed Dart extension/provider/repository/search/network wrappers, lookup caches and
  best-effort native provider synchronization. Settings migration 12 clears retired feed and
  lookup preferences; serialization drops obsolete provider and download-only tag flags.
- Lyrics controls now cover local embedding/sidecar output and presentation. Local artwork
  renders from files; stale HTTP(S) artwork is ignored, including widget artwork. Cover export
  copies local artwork through staged publication and rejects remote URLs. Local metadata,
  tag/lyrics editing, backups, local profiles, playback, SAF and USB remain.
- Mornye is the sole production theme, with existing light/dark, accents, glass and font
  controls. Old Material preferences restore as Mornye. The old Material theme is retained
  only as a test harness for shared-widget fallback coverage.
- Removed the download tutorial simulation and provider deep-link actions; onboarding now
  describes local scanning, playback and folder access. Removed online diagnostic heuristics,
  empty provider settings, stale cache rows and history-exclusion UI. Legacy backup record
  import/export remains for local archive compatibility, explicitly labeled as legacy records.
- Localized message getters reduced from **1627 to 894** (obsolete keys removed or renamed,
  with new local-playback messages added). Rewritten offline copy uses English fallback in
  locales awaiting updated translations, avoiding stale instructions about removed features.
- Removed the release Internet/network-state permissions and obsolete network-security file
  after confirming no FFmpeg loopback/decryption tunnel remains. Debug tooling keeps its
  development Internet permission. Native source archive URLs now use direct codeload URLs
  with the same verified SHA-256 pins, avoiding the earlier redirect/download failure.
- README, changelog, contribution instructions, widget docs and agent guidance now describe
  the offline Android player. iOS launcher-icon generation is removed.

**Phase 8 validation:**
- Flutter analysis: **No issues found**. Focused artwork/theme migration, storage and metadata
  tests: **36 passed**.
- Rust fmt/clippy/workspace tests: **215 passed, 1 existing ignored**; host bindings and Android
  ARM64/ARMv7 Rust builds passed. Python script tests: **12 passed**.
- App and instrumentation Kotlin compilation passed. Android JVM tests: **63 passed, none
  skipped**, including all six host Rust data-job/cancellation ABI tests.
- Release APK built with `flutter build apk --release --target-platform android-arm,android-arm64
  --dart-define=GIT_COMMIT=8609ad06`; **119,269,488 bytes**, Android API 24+, ARM64 + ARMv7.
  Artifact: `build/app/outputs/flutter-apk/app-release.apk`, also copied to
  `/workspace/SpotiFLAC-offline.apk` for download.
- `check_backend_apk.py` passed for Rust and both ABIs. Signature verification passed (APK v2,
  development key); ZIP alignment passed at 16 KB. All **17 ARM64 native libraries** have
  16 KB-or-greater ELF LOAD alignment. Both app libraries contain build commit `8609ad06`.
  The merged release manifest is not debuggable and has no INTERNET/ACCESS_NETWORK_STATE
  permission. No production signing key was configured.
- APK SHA-256: `9ac081b9cd9e4d683077ce51a6eb72c7bb2656625e86f7d9b8e30915348ff683`.
- Graphify refreshed (AST-only): **22956 nodes, 44569 edges, 677 communities**; provenance
  `8609ad06`. No nodes are attributed to the removed share service or production Material theme.
  Vendored C/libusb extractor warnings remain confined to unchanged sources.
- Full `flutter test`: **1615 passed, 3 skipped**. Paging performance test passed; all
  album completeness/filter tests passed with the updated local-library wording.
- Physical-device playback, SAF/USB, statx and launcher-widget checks remain unrun: no Android
  device/emulator is attached. A packaged APK and host tests do not establish device playback.

**Environment / toolchain:**
- In each shell run `source /workspace/toolchains/activate.sh`.
- Installed: Flutter **3.47.7**, Rust **1.99.0** with fmt/clippy, Java **25**, Android platform/
  build-tools **37**, NDK **30.0.16248370**, CMake **4.1.2**, Gradle **9.8.1**.
- Activation sets writable caches, libclang and Java proxy/CA trust. No app server is needed.
  Toolchains live outside the repository; fresh-task restoration has not been verified.

**Untracked (generated/artifacts):** covered by `.gitignore`: `.dart_tool/`,
`.flutter-plugins-dependencies`, `build/`, `lib/l10n/app_localizations*.dart`,
`graphify-out/cache/`, `android/.kotlin/`.

**Known flaky:** `test/library_browse_sqlite_paging_test.dart` has timed out at 30s in earlier
runs; it passed in the final Phase 7 suite.

**Next step:** validate local playback, scanning,
metadata/lyrics saving, backup/restore, SAF/USB, widgets and statx compatibility on an Android
device. Complete translations for newly rewritten offline messages as needed. Do not restore
online APIs to satisfy legacy callers.

**Resume instruction:** read this file, then `git log --oneline -10`; continue from "Next step".

---

## 1. Target architecture (what remains)

**Dart**
- Local library DB: `library_database`, `library_native_adapter`, `library_*`,
  `local_library_provider` (without `network://` branches).
- Playback: `music_player_service`/`_runtime`/`_automix`/`_autoplay`, `music_player_provider`,
  `playback_provider`, `playback_*`, `third_party/audio_service`, `third_party/audioplayers_android`.
- Queue, local album/artist/track browsing, playlists/collections, metadata + lyrics editing,
  replaygain, automix/audio analysis, history/stats, settings/theme/fonts, SAF/USB playback,
  Android home-screen widget.

**Rust** (reduced)
- `core` (pruned of online-support modules), `local` (file operations), `mobile` (local-only
  FFI bridge), `bindgen` tool, `vendor/rustix` and `vendor/libusb1-sys`.
- Keep: `core`'s `cover`, `cue`, `filename`, `isrc`, `media`(+`hires`), `native_audio_analysis`,
  `native_palette`, `tags`, `progress`, `cancellation`, `clock`, `matching`, `text`, local `lyrics`.
- Keep local `mobile` modules: `native_library`, `native_backup`, `native_cache`,
  `native_collections`, `native_id3`, `native_lyrics`, `native_playlists`, `native_playlist_write`,
  `native_xml`, `tags`, `hires`, `data_jobs`, `library_metadata`, `filename`, `local`,
  `lyrics`, `cancellation`, `usb_audio`, `logging`. The former extension-only `native_listing`,
  progress pump and FFmpeg command registry are removed.

---

## 2. Original findings (dependency-grounded; pre-migration baseline)

**Rust crate graph**
```
core        -> (none)                     [CLEAN: no edges to online crates]
network     -> (none)
providers   -> core, network
extensions  -> core, network, providers
mobile      -> core, network, extensions   (providers transitively)
bindgen     -> uniffi only (CLI)
```
- `core/src` has **zero** `use spotiflac_{network,extensions,providers}` hits → pruning core is
  safe if `lib.rs` `pub mod` lines + internal refs are removed.
- `mobile` is **7/… files online** (`extensions.rs`, `ffmpeg.rs`, `logging.rs`, `lyrics.rs`,
  `manager.rs`, `network_tags.rs`, `repository.rs`); the rest are local → **reduce, not delete**.
- Local FFI is bound to online structs: `impl ExtensionManager` methods in `mobile/src/tags.rs`,
  `data_jobs.rs`, `lyrics.rs`, `manager.rs`, `metadata.rs` delegate to `extensions::backend::Backend`.
- `extensions/src/backend/{library,tags}.rs` serve local scan/tag writes but sit on the same
  `Backend` struct that holds `NetworkService` + providers, reaching FS via `ExtensionEnvironment`
  (`cap-std`). Extracting them is a refactor.
- `rustix` must stay (kept `core/src/isrc/native_files.rs:55` + local `mobile` cache/tags use it).
  Dropping it would require replacing that one open-flag call site.
- Android build hardwires Rust: `android/app/build.gradle.kts` (`buildRustBackend` task, sourceSets),
  `proguard-rules.pro` keeps `com.spotiflac.backend.**`, Kotlin `SelectedCoreBackend.kt` /
  `NativeDataJobs.kt` import the generated bindings.

**Biggest product coupling**
- `download_history_provider` is imported by `music_player_provider` (`:5`, `:24-27`, `:148-262`)
  and `playback_provider` (`:3`, `:114-116`, `:362`) plus >28 other files. The player's
  "library identity / playable queue" currently derives from `DownloadHistoryItem`.
  → Removing downloads requires re-pointing the player to the local library DB.

**Platforms / assets**
- Platforms present: `android/`, `ios/` only (no macos/windows/linux/web).
- `third_party/`: keep `audio_service`, `audioplayers_android`; remove `discord/` (35 MB `.gpg`)
  and `spotiflac_discord/` (**pubspec path dep** → must edit `pubspec.yaml` + regenerate lock).
- Online dev tooling/docs to drop: `apps.json`, `NETWORK_STORAGE.md`, `crowdin.yml`, `cliff.toml`,
  `renovate.json`, `docs/artist_concerts.md`, iOS/Discord/SMB scripts.
- No `.github/` workflows in the working tree.

---

## 3. Decisions (RESOLVED)

- **D1 — Player data source: (a) re-point to the local library DB.** Delete download history
  entirely; `music_player_provider` / `playback_provider` read from the local library DB.
- **D2 — Home tab: (b) keep `home_tab` as a local "recent access" hub** (recently played/added,
  local albums). Drop Explore/online feed only.
- Minor defaults (accepted): remove `user_profile`/donate UI; remove `hires_check_service`
  (download-era fake-hi-res check) but keep `core`'s authenticity check; keep `automix`,
  `replaygain`, `palette`, `statistics`, `backup/restore`, USB bit-perfect.

### Vision refinements (user, 2026-10-16)

- **V1 — Mornye theme only.** Remove all other themes and the theme picker; Mornye is the sole
  look. Phase 8 retains light/dark, Mornye accents, glass and local font controls; the
  alternate Material theme and picker are removed.
- **V2 — Home feed → local.** Rewire the home feed provider off Apple Music to local content.
  TBD: which sections (Recently Added / Recently Played / Most Played / local Albums / Favorites /
  Artists)?
- **V3 — Reuse Mornye "online" theming for local artist / album / playlist screens**, replacing
  the old local styling. TBD: confirm the old local screens/styling are deleted outright.
- **V4 — Remove all online-service settings** (extensions/store, providers, downloads, network
  storage, Discord, updates/remote-config, profile, donate, plus online rows inside
  Music/Library settings).

Impact on phases: Phase 5 keeps a **localized** home feed (not dropped); adds a **theming
consolidation** workstream (Mornye-only + style port); Phase 8 settings purge = all online settings.

---

## 4. Phased plan (one commit per phase)

### Phase 1 — Platform & repo-hygiene trim (no Dart code impact)
Remove: `ios/`; `third_party/discord/`; `apps.json`, `NETWORK_STORAGE.md`, `crowdin.yml`,
`cliff.toml`, `renovate.json`, `docs/artist_concerts.md`; scripts `build_ios.sh`,
`check_backend_ios.py`, `test_check_backend_ios.py`, `ios_ffmpeg_capabilities.m`,
`README_ios_ffmpeg_capabilities.md`, `prepare_discord_sdk.py`, `test_prepare_discord_sdk.py`,
`setup_discord_sdk.sh`, `test_network_smb*_server.py`; `assets/readme/` (if README trimmed).
Edit: `analysis_options.yaml` excludes; `.gitattributes` (vendor rules) only if needed.
Verify: `flutter build apk` still succeeds; no Dart touched.
Note: do **not** touch `rust_backend/vendor/` — it is referenced by `[patch.crates-io]`.

### Phase 2 — Discord removal (Dart + pubspec + Gradle + manifest)
Remove: `third_party/spotiflac_discord/`; `lib/services/discord_presence_service.dart`,
`discord_artwork_resolver.dart`; `lib/widgets/discord_presence_settings.dart`; Discord refs in
`main_shell.dart`, `music_player_runtime.dart`, `settings/playback_settings_page.dart`;
`models/settings.dart` `discordRichPresenceEnabled`; l10n `discordPresence*` keys (all 20 arb);
`flutter_secure_storage` only if no other user (verify `secure_storage_options.dart`);
`integration_test/discord_sdk_test.dart`, `test/discord_*_test.dart`.
Edit: `pubspec.yaml` (drop `spotiflac_discord`), `pubspec.lock` (regen), `android/app/build.gradle.kts`
(Discord AAR block, `discordSdkEnabled`, `pickFirsts`), `AndroidManifest.xml` (Discord
`tools:node="remove"`), `scripts/build_android.sh` + `test_build_android.py` + `check_backend_apk.py`.

### Phase 3 — Updater / remote-config / announcements
Remove: `services/update_checker.dart`, `apk_downloader.dart`, `app_remote_config_service.dart`;
`screens/upgrade_intro_screen.dart`; `widgets/update_dialog.dart`, `app_announcement_dialog.dart`;
`settings/donate_page.dart`; `services/upgrade_intro_service.dart`.
Edit: `main_shell.dart` (remove `_checkUpgradeIntro`, `_checkForUpdates`, `_checkAppAnnouncement`,
imports), `settings/settings_tab.dart`, `settings/app_settings_page.dart`.
Manifest: drop `REQUEST_INSTALL_PACKAGES`, APK FileProvider.

### Phase 4 — Network storage (SMB/WebDAV) removal
Remove: `services/network_*` (storage_service, smb_client, certificate, download_staging,
audio_analysis_input, library_scanner, metadata_service, delete, upload, error),
`screens/network_storage_screen.dart`.
Edit: `local_library_provider.dart` (drop `network_library_scanner` import + `network://` branches),
`track_metadata_screen.dart` (network branches), `providers/settings_provider.dart`,
`files_settings_page.dart`, `pubspec.yaml` (drop `dart_smb2`), `assets/licenses/libsmb2.txt` +
`pubspec.yaml` assets list.
Caution: verify `network_security_config.xml` (localhost cleartext used by the FFmpeg decrypt
tunnel) before removing; likely keep localhost entry or drop the file only after confirming.

### Phase 5 — Extension system + online providers + online search (Dart)
Remove providers: `extension_provider*`, `repo_provider`, `explore_provider`,
`weekly_releases_provider`, `track_provider`, `preview_player_provider`; `download_fallback` wiring.
Remove services: `cross_extension_share_service`, `extension_storage_service`,
`metadata_autofill_service`, `batch_metadata_re_enrich`, `local_track_redownload_service`,
`weekly_releases`, `motion_artwork_download`, `motion_artwork_proxy` (verify), `hires_check_service`.
Remove screens: `repo_tab`, `screens/repo/*`, `weekly_releases_screen`, `artist_concerts_screen`,
`concert_detail_screen`, `home_tab_explore`, `home_tab_search_results`.
Remove widgets: `explore_featured_section`, `extension_row`, `extension_repo_card`,
`cross_extension_share_sheet`, `hires_check_card`, `open_on_platform_sheet`, `metadata_candidate_tile`,
`re_enrich_*`, `download_service_picker`.
Remove settings pages: `extensions_page`, `extension_detail_page`,
`lyrics_provider_priority_page`, `metadata_provider_priority_page`, `provider_priority_page`,
`provider_priority_list_page`, `profile_settings_page`; `models/extension.dart`, `artist_concert.dart`.
Edit: `home_tab*.dart`, `album_screen`, `artist_screen`, `playlist_screen`,
`library_tracks_folder_screen`, `mornye_library_screen`, `track_metadata_edit_sheet`,
`track_metadata_lyrics`, `queue_tab*`, `main_shell.dart`, `settings_search_catalog.dart`,
`settings_tab.dart`, `settings/lyrics_settings_page`, `settings/metadata_settings_page`,
`settings/cache_management_page.dart`.

### Phase 6 — Download engine removal + player re-point  (largest Dart phase; depends on D1) — DONE (`f3ab83e`, `dfd7f43`)
Remove providers: `download_queue_provider*` (10 files), `download_queue_state`,
`download_verification_retry_guard`; and per D1, `download_history_provider*` +
`models/download_item(.g)`, `download_result`, `download_history`.
Remove services: all `download_*`, `downloaded_embedded_cover_resolver`, `native_download_history`,
`verification_notification`; remove `screens/downloaded_album_screen.dart`; download widgets
(`downloadable_cover`, `download_queue_feedback`, `preview_button`, `download_service_picker`).
Edit (re-point to local library): `music_player_provider.dart`, `playback_provider.dart`,
`now_playing_screen.dart`, `library_*_provider`, `services/music_player_runtime.dart`,
`services/playback_metadata.dart`, `main.dart` (extension init, download wiring, verification
notifications), `main_shell.dart`, `queue_tab*`, settings download pages/rows.
Android: remove `DownloadService*`, `NativeDownloadFinalizer*`, `NativeFinalizationPolicy*`,
`SafDownloadHandler.kt`, `DownloadQueueWidgetProvider.kt`, `BackgroundWorkService` download path.

### Phase 7 — Rust backend reduction  (riskiest; itself sub-phased)
Suggested sub-order (mirrors the crate graph):
1. **Prune `core` online-support modules**: `metadata::{deezer,musicbrainz,share,reenrich,catalog}`,
   `resolver`, `downloads`, `app_version`, lyrics `{config,payloads,lrclib,errors}`; remove their
   `pub mod` lines in `core/src/lib.rs` and fix internal refs (`metadata/reenrich.rs:5`).
   Verify: `cargo test -p spotiflac-core`.
2. **Re-home local `extensions::backend` pieces** (library scan + tags) into `core` or a new
   `local` module, decoupled from `ExtensionEnvironment`/`NetworkService`.
3. **Reduce `mobile` to local-only**: drop `manager.rs`, `extensions.rs`, `repository.rs`,
   online `metadata.rs`/`lyrics.rs` methods, `network_tags.rs`, `tags.rs:243` cover download;
   re-point local `impl` methods onto the re-homed local type. Keep `bindgen` + regen bindings.
4. **Delete `providers`, then `network`, then `extensions`** once unreferenced.
5. **Update build config**: `rust_backend/Cargo.toml` (members, workspace deps, patch), `Cargo.lock`,
   `scripts/build_rust_backend.sh` (drop ios), `scripts/check_rust_backend.sh`,
   `scripts/check_android_statx.sh`, `android/app/build.gradle.kts` (sourceSets/build task),
   Kotlin `SelectedCoreBackend.kt` / `NativeDataJobs.kt` / `CoreBackend.kt`, `SpotiFLACBackend.podspec`,
   android tests for extensions/downloads (remove).
Verify: `cargo test`, `scripts/build_rust_backend.sh android`, full `flutter build apk`, run app.

### Phase 8 — Dependencies, l10n, docs, final polish — IMPLEMENTED (`8609ad06`)
- `pubspec.yaml`: drop now-unused online deps (`http`, `cached_network_image`, `connectivity_plus`,
  `url_launcher`, `receive_sharing_intent`, `xml`, `html`, `archive`, `crypto`, `flutter_cache_manager`,
  `flutter_secure_storage` if unused); drop `ios: true` from `flutter_launcher_icons`; regen
  `pubspec.lock`.
- l10n: prune online-only keys from `app_en.arb` + locales.
- Docs: trim `README.md`, `CHANGELOG.md`, `CONTRIBUTING.md`, `docs/player_widgets.md`, `AGENTS.md`.
- Final: `flutter analyze`, `flutter test`, `bash scripts/check_rust_backend.sh`,
  `flutter build apk`, `graphify update .`.

---

## 5. Risk resolution and remaining verification

- Rust/core/local/FFI coupling (R1) is resolved by Phases 7-8; native tests and both Android
  Rust ABI builds pass. Device storage/audio validation is still required.
- Player/download-history coupling (R2) was resolved in Phase 6; Phase 7 removed history
  attachment/exclusion. Legacy local backup records remain readable for archive compatibility.
- Discord dependency and asset cleanup (R3/R4) is complete; local native license assets remain.
- Secure-storage coupling (R5) ended with provider credentials; the unused plugin is removed.
- The old FFmpeg tunnel is absent (R6); release Internet permission is removed and the
  packaged manifest was audited. Debug builds retain Internet for Flutter tooling.
- External CI configuration (R7) is not present in this checkout and has not been inspected.
- Validate the APK on real hardware: local playback, background controls, scans, metadata and
  lyrics, backups, SAF/removable storage, USB routing, widgets and older-Android statx handling.
- New offline copy uses English fallback where translations need updating. The APK uses the
  development signing key; configure a production key before distributing official updates.
