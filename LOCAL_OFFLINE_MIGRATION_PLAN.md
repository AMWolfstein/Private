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

---

## Progress

_Last updated: 2026-10-17_

**Status:** IN PROGRESS. Phases 1-5 committed (Phase 5 removed the online UI/provider layer in
sub-phases 5a/5b/5c). Phase 6 next. Vision refinements V1-V4 captured.

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

**Phase 5 summary:** the entire online extension/provider/search UI layer is gone; what remains
online-coupled (`extension_provider` registry, `track_provider`, Mornye home search) is consumed
only by the download engine and is removed with it in Phase 6. Two now-dead settings
(`homeFeedProvider`, explore-feed cache row) are deferred to the Phase 8 settings purge (V4).

**Environment / toolchain:**
- Flutter **3.47.7** (Dart 3.13.5) installed at `~/flutter`
  (use `export PATH="$HOME/flutter/bin:$PATH"`).
- Rust (`cargo`/`rustc`) NOT installed yet → `build_rust_backend.sh` and `flutter build apk`
  cannot run until rustup is installed (needed before Phase 7).
- Verification: baseline (pre-migration) and post-Phase-2 `flutter analyze` → **No issues found**.
  Script changes: `cd scripts && python3 -m unittest` (12 tests OK).

**Untracked (generated/artifacts):** `.dart_tool/`, `.flutter-plugins-dependencies`, `build/`,
`lib/l10n/app_localizations*.dart` (regenerated), `graphify-out/cache/`. No root `.gitignore`
exists (remove `cache/` or add one).

**Known flaky:** `test/library_browse_sqlite_paging_test.dart` times out at 30s here (pure perf
test, unrelated to migration). Post-Phase-5 full suite: 2034 passed, 3 skipped, 1 failed (that
same perf test). `flutter analyze` → No issues found.

**Next step:** Phase 6 — download engine removal + player re-point to the local library (D1).
This also removes the extension registry, `track_provider` and Mornye home search.

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
- `core` (pruned of online-support modules) + a local-only FFI bridge (reduced `mobile`,
  or a new local crate) + `bindgen` tool + `vendor/rustix` + `vendor/libusb1-sys`.
- Keep: `core`'s `cover`, `cue`, `filename`, `isrc`, `media`(+`hires`), `native_audio_analysis`,
  `native_palette`, `tags`, `progress`, `cancellation`, `clock`, `matching`, `text`, local `lyrics`.
- Keep local `mobile` modules: `native_library`, `native_backup`, `native_cache`,
  `native_collections`, `native_id3`, `native_lyrics`, `native_playlists`, `native_playlist_write`,
  `native_listing`, `native_xml`, `tags`, `hires`, `data_jobs`, `library_metadata`, `filename`,
  `cancellation`, `progress`, `usb_audio`, `ffmpeg`(local registry), `logging`.

---

## 2. Key findings (dependency-grounded)

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
  look. TBD: keep light/dark and/or dynamic color *within* Mornye, or one fixed variant?
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

### Phase 6 — Download engine removal + player re-point  (largest Dart phase; depends on D1)
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

### Phase 8 — Dependencies, l10n, docs, final polish
- `pubspec.yaml`: drop now-unused online deps (`http`, `cached_network_image`, `connectivity_plus`,
  `url_launcher`, `receive_sharing_intent`, `xml`, `html`, `archive`, `crypto`, `flutter_cache_manager`,
  `flutter_secure_storage` if unused); drop `ios: true` from `flutter_launcher_icons`; regen
  `pubspec.lock`.
- l10n: prune online-only keys from `app_en.arb` + locales.
- Docs: trim `README.md`, `CHANGELOG.md`, `CONTRIBUTING.md`, `docs/player_widgets.md`, `AGENTS.md`.
- Final: `flutter analyze`, `flutter test`, `bash scripts/check_rust_backend.sh`,
  `flutter build apk`, `graphify update .`.

---

## 5. Risks

- **R1 (high):** Rust local FFI is bound to online structs; Phase 7.2–7.3 is a genuine refactor.
  Budget the most time here; consider a spike branch first.
- **R2 (high):** `download_history` ↔ player coupling (D1). Decide before Phase 6.
- **R3 (med):** `spotiflac_discord` is a pubspec path dep → must edit pubspec + lock with the delete.
- **R4 (med):** pubspec-gated assets/licenses; mirror removals in `pubspec.yaml`.
- **R5 (med):** `flutter_secure_storage` may serve non-Discord secrets (extension storage *and*
  other) — verify before dropping.
- **R6 (low):** keep `INTERNET`/`network_security_config` until the FFmpeg decrypt tunnel is verified
  to not need localhost.
- **R7 (low):** no in-repo CI; confirm external CI doesn't invoke removed crates/scripts.
