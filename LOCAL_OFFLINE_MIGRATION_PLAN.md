# Local / Offline / Android-only Migration Plan

> Identity normalization (T16, 2026-10-28): historical names, paths and command strings below were mechanically renamed. Original evidence used the former terms; no listed checks were rerun by this rename. Encoded upstream/download identifiers retain their actual destinations.

Goal: convert `sistrum` from an **extension-driven online downloader** into a
**local, offline, Android-only music player**.

Chosen scope (confirmed):
- Rust backend: keep local parts, strip online.
- Remove: extensions + providers + download engine, network storage (SMB/WebDAV),
  non-Android platforms, online UI surfaces, Discord presence.
- Approach: plan doc, then phased commits (one reviewable commit per subsystem).

Verification for every phase: `flutter analyze`, `bash scripts/check_rust_backend.sh`
(cargo fmt/clippy/test), `bash scripts/build_rust_backend.sh android`, then
`flutter build apk`; run `graphify update .` after code changes.
**Current user instruction (2026-10-19): restore the former metadata-page local actions
in the new song ellipsis menus, retaining Edit Metadata and Audio Quality Analysis, and fix
popover placement so it follows the tapped ellipsis. Keep the metadata page removed.**

---

## Progress

**FFmpeg minimal package (2026-10-30):** FFmpeg moves from `ffmpeg_kit_flutter_new_audio` 2.5.7 to `ffmpeg_kit_flutter_new_min` 3.6.7, which wraps the same minimal native build (`ffmpeg-kit-min` 2.2.3). The app only encodes FLAC and PCM and copies or decodes other streams, so the smaller build covers it. The arm64 native libraries shrink from about 19.7 MB to 14.9 MB, and the release APK from 56.5 MB to 49.0 MB (SHA-256 `29709a3bd6b0edb394b24e3fa5d66a0e4f27bd718956c0957e18ad4987b4a697`). The androidTest FFmpeg fixtures still use the audio AAR, because they assert encoders for removed conversion features. Verification: `flutter analyze` clean; full `flutter test` 2,250 passed, exit 0. Code commit `a73ce45`. Superseded by the FFmpeg revert below.

**FFmpeg revert (2026-10-30):** the switch to `ffmpeg_kit_flutter_new_min` 3.6.7 is reverted (`95778bf`). FFmpeg is back on `ffmpeg_kit_flutter_new_audio` 2.5.7 (`com.antonkarpenko:ffmpeg-kit-audio` 2.2.3), and the license asset names the same package. The release APK has not been rebuilt on this tree, so the 49.0 MB figure above no longer describes the current code. Verification: `flutter analyze` clean; full `flutter test` 2,250 passed, exit 0.

**Setup and shuffle fixes (2026-10-30):** Play all and shuffle queue the library rows they already read, skipping a second lookup, and log paging, preparation and playback timings (`e1b6cf2`). Choosing a music folder no longer holds the setup step until the first scan finishes (`2ec2cba`). The five local-player guide pages are one setup page, so setup counts five steps on Android 13+ (`f667f0d`). Drafts are version 4; older drafts are mapped onto the single guide page (`df62fa1`). Verification: `flutter analyze` clean; full `flutter test` 2,250 passed, exit 0. Graph `bb29e49`.

**Album Artists list (2026-10-30):** the Artists list reads track-artist credits only. A new Album Artists row in the Library overview, directly below Artists, lists album-artist credits with their own cover and sample lookups. Artist pages still match both credit types. Verification: `flutter analyze` clean; full `flutter test` 2,251 passed, exit 0. Code commit `46dc9aa`.

**Lyric direction and immersive drift (2026-10-30):** synced Arabic words sweep from the right on RTL lines, and shared lyric lines align by their own direction (`lyric_direction.dart` now holds the shared helper). The immersive player cover drifts with the album Ken Burns, paused while lyrics show. Verification: `flutter analyze` clean; full `flutter test` 2,253 passed, exit 0. Code commits `622abd3`, `0412f1b`, and the Ken Burns commit.

**Player drift in Normal view (2026-10-30):** the Normal view's square cover uses the album Ken Burns drift too, under the same setting, with the same stop rules and paused while lyrics show. Verification: `flutter analyze` clean; full `flutter test` 2,253 passed, exit 0. Code commit `Normal view drift`.

**Folder split (2026-10-30):** the last three `flat_dirs` findings are resolved. `test/` mirrors the `lib/` layout for tests whose source has the same name, and groups the rest by domain (library, ui, lyrics, playback, platform). `lib/widgets/player` is split into sheets, queue, lyrics, controls, layout and artwork; `lib/constants`, `lib/models`, `lib/navigation` and `lib/theme` move under `lib/core`. Imports rewritten; no behaviour change. Verification: `flutter analyze` clean; full `flutter test` 2,251 passed, exit 0. Code commit `8cc680e`; graph `6c875d6`.

**Folder restructure (2026-10-30):** `desloppify` flagged ten directories as overloaded (`flat_dirs`). Files moved into feature subfolders with `git mv`: `lib/services/library` (collections, database, browse, scan, metadata, covers), `lib/services/playback` (music_player, automix, autoplay, session, notification, audio, stats, core), `lib/utils`, `lib/screens/library`, `lib/screens/settings`, `lib/widgets/glass`, `lib/widgets` and `integration_test`. Part files moved with their owners; imports, exports and parts rewritten, no behaviour change. Verification: `flutter analyze` clean; full `flutter test` 2,249 passed, exit 0. Code commit `9d2e7d0`; graph refreshed on the merged branch.

**Code-health pass (2026-10-28):** a `desloppify` review queue drives structural fixes, one reviewed finding per change.
First item: the forwarding `FFmpegService` facade is gone; callers use `FFmpegMetadata`, `FFmpegProbe`, `FFmpegReplayGain`,
`FFmpegCue` and `ffmpeg_models.dart` directly. Second: `PlayableMedia` moved to `lib/models/playable_media.dart` (queue
restoration no longer imports the player engine) and album route identity (`DetailPage`) moved to
`lib/utils/detail_page_route.dart`. Third: update checks distinguish a verified "no newer release" (null) from an unreachable or
unverifiable release list (`UpdateCheckException`), and Settings > Updates offers a retry instead of claiming the app is
up to date. Fourth: FFmpeg metadata writes throw `FFmpegMetadataFailure` with a concise cause, and the metadata save result keeps
it (`MetadataSaveResult.failed(error)`) instead of dropping it. Fifth: small clarity fixes — profile-save rollback keeps the
original failure, `saveMetadata` became `buildMetadataTags`, the full player lost its fixed-opacity fade wrapper, the
storage-permission ternary collapsed, Loved toggling is inlined, and scan preparation no longer keeps the unused
`resolvedPath` placeholder. Sixth: full and incremental scans share `_finishScanSuccess` for the completion policy, and
local-library preferences resolve `SharedPreferences` per operation instead of caching a failed first attempt. Seventh: native
metadata edits decode once into `MetadataEditResult` (`completed`/`ffmpegStaged`/`failed`) shared by the persistence and
ReplayGain paths, the MP3/M4A FFmpeg writers are named `replaceMetadataInMp3`/`replaceMetadataInM4a` and lost their
unsupported preservation option, and the dispatcher reports unsupported preservation for them instead of running a
guaranteed-refusing writer. Eighth: `UnifiedLibraryItem` requires its `LocalLibraryItem` and derives every track field from
it; the one-value source enum, duplicated fields, unused forwarding getters and absent-record conversion branches are gone,
while the selection and collection keys are unchanged. Ninth: first-run setup no longer requires all-files access on Android 10+; the
storage step picks a music folder through the same SAF helper as Local Library settings (or can be skipped), and an existing
folder satisfies it, so `MANAGE_EXTERNAL_STORAGE`, `READ_MEDIA_AUDIO` and the Android 11 dialog are gone from setup. Tenth:
`deleteLocalLibraryTracks` owns the whole local deletion policy (CUE protection, one physical delete per path, index cleanup,
partial success), and the song menu, batch service and album screen all route through it while keeping their own confirmation,
selection exit and snackbar. Eleventh: `MetadataIndexReconciler` owns the post-save reread/map/artwork/upsert sequence and
returns indexed-or-stale, so the song menu only opens the editor, reloads the provider and reports the outcome. Twelfth: track-list
playback resolves the matched `LocalLibraryItem` rows and builds its queue through `playableFromLocal`, keeping the library ID,
audio facts and local-only artwork, while `resolveTrackFilePaths` stays a path-only projection for M3U export. Thirteenth: QueueTab
and its seven parts moved to `lib/screens/library/`, HomeTab and its two parts to `lib/screens/home/`. Fourteenth: the flat services
directory split into `lib/services/library/` (database/query/schema helpers), `lib/services/playback/` (player, session and AutoMix)
and `lib/services/ffmpeg/` (FFmpeg operations), with shared infrastructure left at the root. Fifteenth: widgets split into
`lib/widgets/audio_analysis/` (the analysis library and parts), `lib/widgets/player/` and `lib/widgets/glass/`, with shared app
controls kept at the root. Sixteenth: the SQLite startup tests open a real database through `openAppDatabase` (FFI factory,
temporary documents directory) and assert the PRAGMA values for fresh and existing schemas, while the trigram tests drive
`createTrigramFtsIndex` through a recording executor instead of reading source text. Analyze and the full `flutter test` pass.

**Album Ken Burns (2026-10-28):** Sistrum album headers drift slowly (`AlbumKenBurns`, 28 s cycle, zoom 1.04-1.10). Appearance >
Animated artwork (`animatedAlbumArtwork`, default on, in backups) switches it off. It stops for reduced motion, glass off or
low-end devices, covered routes and a page scrolled past the cover; playlists, Loved and artists are unchanged. Online artwork
and lyrics (`docs/ONLINE_SOURCES_PLAN.md`) wait until after the Media3 migration. Analyze and the full `flutter test` pass; the
look and speed need checking on a device.

**Version reset (2026-10-28):** app version is now 1.0.0 build 1 (`pubspec.yaml` 1.0.0+1, `AppInfo`). Earlier entries below keep their historical 5.1.1 build numbers.

**Second dead-code pass (2026-10-28):** removed `LocalLibrarySortMode`, `LocalLibraryItem.matchKey`, write-only fields
(`fadeOutDuration`, `latestScanned`, `CoverColors.dominantColor`, `BackupBundle.appVersion`, `pickSafTree(forSetup)`),
`readLyricsWithSafCopy` and its tests, the collections state export worker chain (`exportLibraryCollectionsState`), the
unused `CancellationRegistry` waker, `cancel_active` and reset methods, and the `lifecycle-runtime-ktx` dependency.
Analyze, full `flutter test` and `cargo test --offline` pass; Gradle and Kotlin checks and device tests are not run.

**Whole-repo dead-code scan removed (2026-10-28):** unused Dart members (`sistrumArrowForward`, three `LibraryDatabase`
getters, `readPositiveBitrateKbps`, `favoriteActionLabel`, `UpdateChecker.currentVersion`, unused icon-map arms), the
`concert_calendar` MethodChannel in `MainActivity.kt`, the `claxon` and mobile `sha2` Cargo dependencies, the
`network_tls` fixtures, and test-only code (player/autoplay configuration wrappers moved into the test, collections JSON
export, native snapshot publication, grid quality label and badge highlight policy, `normalizeScannedAudioMetadata`,
`isPlaceholderQualityLabel`, the `activeLyricIndices` oracle, `CoverPalette.cacheKeyFor`). `CoverPalette.debugClearMemory`
stays (a `@visibleForTesting` seam). Verified with analyze, full `flutter test` and `cargo test --offline`; Kotlin
checks and device tests are not run.

**Risky leftovers removed (2026-10-28):** the single-folder settings (`localLibraryPath`/`localLibraryBookmark`), iOS bookmark
plumbing and single-folder source migration, the library (v20) and collections (v4) schema upgraders (the versions stay
pinned by Rust, older databases are no longer upgraded), upgrade-only SQLite helpers, the `EXISTS:` history marker and
extension-stripped path keys (Dart and Rust, fixture regenerated). Kept because they are stored data or persisted
identity: the `legacy` source id and its placeholder row, the `builtin:`/`isrc:` collection keys and `Track` provider
fields, and lyrics provider-credit parsing. The `bookmark` column stays in the library_sources table (unused).

**Old-install migrations removed (2026-10-28):** theme/glass/locale/equalizer key fallbacks, legacy notification and widget
actions, the old playback-channel cleanup, the retired cover cache, the download queue table (app-state DB v6), the
SharedPreferences collections import, dead download-filename/tag helpers, iOS picker/notification options and the legacy
mod-time backfill. Kept: library DB v20 and collections DB v4 upgrade code (Rust pins those versions), path-key and lyrics
provider parsing (persisted data and Rust parity), the `legacy` source id and single-folder source migration, the iOS
bookmark plumbing on library sources, and the non-native Dart fallbacks. The Kotlin changes were not run through
`scripts/check_android.sh` (no Gradle wrapper in this checkout).

**Old-app leftovers removed (2026-10-28):** iOS container/now-playing/notification/audio-output code, the local-library
on/off setting and `includeLocal` query flags (the library is always on), Artist Tag Mode plumbing in Dart and the Rust tag
writer (including the embed-only FLAC path), the unused `openContentUri` bridge and four orphaned l10n keys. Kept on
purpose: the non-native Dart fallbacks (they are the host-test seams) and the shared Apple-style theme branches.
Device validation is still the owner's.

**Legacy removal (2026-10-28):** the download-history database/model, history and extension payloads in backups
(Dart and Rust), the legacy backup envelope, the downloaded-source filter and excluded-downloads count, dead Track
fields and Kotlin policy, and old string keys are gone. Backups are `.sbk`, format v3 only; older backups no longer
restore by owner decision. Rust cancellation has a single request domain.

**Updater restored (2026-10-28):** GitHub-release update check, Settings > Updates page above About (Check now, check and preview-channel switches), update
dialog with in-app APK download and install, 28 strings in all locales. The release manifest now has INTERNET,
REQUEST_INSTALL_PACKAGES and a FileProvider. `AppInfo.githubRepo` is `amwolfstein/private` until the public
repository exists (a private repo yields no updates). Install on device is the owner's to test.

**Library/player UI batch (2026-10-28):** Library pages have no search (the bottom Search tab
remains); Songs shows Play/Shuffle like albums; the player and media notification use a heart;
the artist favorite/shuffle buttons use the tonal album style; Listening statistics is a tab
between Home and Library; the cover resizer is gone from Edit metadata; lyric lines take their
direction from the first strong letter; Equalizer band names start-align. Device validation is
still the owner's.

**Upstream ledger 5.1.1 → 5.2.6 (2026-10-28):** every upstream commit in `5a895265..c90ec647`
(533) checked one by one; verdicts in `reviews/upstream-v5.1.1-v5.2.6-ledger.md` (144 recorded
earlier, 12 ported now, 339 not applicable, 38 translations). Ported as U-509..U-516: autoplay
learning default and reset confirmation (`b3f4244`), far-line lyrics test (`78cac12`), FFmpegKit LGPL
notices (`eb44a8e`), and adaptive scrollable sheets, choice rows, log level sheet, Beta badge,
statistics skeleton and 840dp tablet centring (`f609257`). `flutter analyze` clean; full
`flutter test` passed (1870, 4 skipped). Not done: the upstream translation import; device testing
belongs to the owner.

**T16 — owner-wide Sistrum identity normalization (2026-10-28), verified locally, not committed:**
extends T15 to internal identifiers, file names and documentation. The owner's explicit
request overrides the prior branding-preservation rule; every basename `README.md` stays
unchanged. Legacy persistence/backup support uses encoded identifiers with unchanged
runtime values. Actual upstream and published APK destinations remain percent-encoded;
historic legal authorship is preserved, not reassigned. Historical evidence below has
mechanically normalized terms, not newly executed commands. Verified on the working tree:
`flutter gen-l10n` exit 0; `flutter analyze` No issues found; full `flutter test --concurrency=1`
+1864 ~3, all passed (exit 0); `scripts/check_rust_backend.sh` exit 0, 216 passed / 0 failed;
`scripts/check_android.sh` BUILD SUCCESSFUL, 97 tests = 96 passed / 1 skipped; host UniFFI
bindings regenerated from `com.sistrum.backend`; `sync_opencode_agents.py --check` exit 0.
Compatibility fixes made during verification: legacy-channel cleanup targets only the escaped
former channel with a current-channel guard; native backup readers accept the encoded legacy
magic; widget receives the encoded former action. Not run: ARM64 native build, instrumentation,
device checks. No commits made yet.

**T15 — Sistrum identity (2026-10-28):** source `dba4480`, graph `ebfcdb1`. Renamed the base app to `com.amwolfstein.sistrum` / **Sistrum** and the side-by-side variant to `.local` / **Sistrum Local**; moved every Android source set and updated JNI, channels, manifests, reflection keeps, widget names and visible translated copy together. Preserved backup magic/file names, settings/DB identities, equalizer format, notification action IDs and the internal UniFFI/Dart package names. Old Sistrum backups still load in host compatibility fixtures. The owner selected the transparent `logo/logo.png` after the two supplied images were confirmed to contain different artwork: full-colour inputs/in-app assets preserve it exactly; launcher/splash use the dark reference-corner colour, while themed/notification icons use alpha silhouettes. Android 12 splash uses a safe inset in light and dark. Four scoped reviewers PASS; three branding checks PASS; analysis clean. Full serial Flutter: 1,857 passed / 3 skipped / 1 failed (a missed Korean `SpotifyFLAC` brand); fixed/re-reviewed and its file rerun 22 passed / 0 failed, full suite not rerun per task rule. Android host: 96 passed / 1 skipped / 0 failures. ARM64 JNI and instrumentation source compilation PASS; all 18 compiled JNI exports use the new package. No APK, signing or device/instrumentation execution; launcher/themed icon/splash/notification appearance and real old-backup restore remain owner checks. The retired Compose Sistrum app must be uninstalled before installing this same-ID app. Existing RTL/copy and audit deferrals remain open. Details: `reviews/VERIFICATION.md`.

**Upstream port batch 17C, Sistrum 5.2.6 (2026-10-27):** code `da3dc62`, `d6c1a86`, `c29d361` (each with its graph commit). Media controls follow metadata and artwork that arrive after a track starts; AutoMix lands the next song on the outgoing beat, verifies the landing (falling back to a plain crossfade), holds phase with bounded rate corrections and uses a bass handoff for uncertain beats. Analysis clean; full Flutter 1,831 passed / 4 skipped; Rust 215 passed / 1 ignored, Clippy clean. Android host unit tests and instrumentation NOT RUN (no Android SDK here). No APK or device run; crossfade by ear is the owner's check. Upstream checked through `c90ec647`. Details: [UPSTREAM.md](<reviews/UPSTREAM.md>) U-506 to U-508.

**Upstream port batch 17B, Sistrum 5.2.6 (2026-10-27):** code `8e42f78`, `db7cb11`, `55167bf` (each with its graph commit). Settings subpages scroll their last rows above the floating bar; Songs and Albums sort by file size from a lazily filled, trigger-invalidated `track_file_sizes` table; Local Library lists the files the last scan of each folder could not read, with reasons. Analysis clean; full Flutter 1,808 passed / 4 skipped; Rust 213 passed / 1 ignored, Clippy clean. Android host unit tests NOT RUN (no Android SDK here). No APK or device run. Details: [UPSTREAM.md](<reviews/UPSTREAM.md>) U-503 to U-505.

**Upstream port batch 17A, Sistrum 5.2.6 (2026-10-27):** code `0acf9ee` (graph `9b46d11`) and `900239c`. Library scans index untagged MP3/MP4, raw ADTS AAC and ID3-prefixed FLAC instead of reporting errors; tag edits keep an ID3 prefix in front of FLAC; SAF and descriptor reads retry transient failures. The Flutter 3.47.7 semantics geometry crash is backported as an SDK patch applied by `scripts/prepare_flutter_sdk.dart`. Analysis clean; full Flutter 1,792 passed / 4 skipped; Rust 212 passed / 1 ignored, Clippy clean; `test_build_android.py` 6 passed. Android host unit tests NOT RUN (no Android SDK in this container). No APK or device run. Details: [UPSTREAM.md](<reviews/UPSTREAM.md>) U-501, U-502.

**Languages restored (2026-10-27):** code `e4d2463`, graph `467f435`. Reverts the English-only change `b06602f` by owner request. Restores the 19 translation arb files, the Appearance language picker, the setup language step, the saved locale, the Android locale config and the Indonesian player widget strings. The strings added since the translations were removed (about 6,800 across 19 locales) were machine-drafted per locale; untranslated keys fall back to English, and several terms are flagged for native review. ICU plural branches shadowed by `=1` were removed. `supported_locales.dart` lists every locale instead of the old 70% filter. Checks: `flutter gen-l10n` exit 0, 0 ICU warnings; `flutter analyze` No issues found; full serial Flutter 1,784 passed / 3 skipped / 0 failed; `check_android.sh` BUILD SUCCESSFUL, 95 tests = 94 passed + 1 skipped. Setup-recovery counters now show 9 pages. No APK, instrumentation or device run. Push NOT RUN: GitHub HTTPS credentials are missing.

**Dead-code removal, audit T14 (2026-10-27):** code `506b892`, graph `35e4e09`. Removed the unused SAF staged-writer island, two private AudioService wrappers, `HistoryMaintenanceUpdate`, `shuffleLibrary` (closing DATA-002), `navigateToTrackAlbum`, `displayFormatForCodec`, the download-completion policy island (the live count/page helpers stay), two orphan gesture widgets with their tests, `PlayerPlaybackMode`, and six unused README images plus `logo.svg`. Library schema v20 drops the write-only lookup-summary table and its six triggers (triggers first), with Rust `SCHEMA_VERSION` 20; a real v19 fixture proves the upgrade. The live SAF write path, `NativeReplayGainPolicy` and the plugin/FFI/JNI/test seams are untouched. Required dead-code, Flutter, Kotlin/SAF and data-integrity reviews PASS. Analysis clean; full serial Flutter 1,783 passed / 3 skipped / 1 failed (a defect in the new v19 test, fixed, file rerun 6/6, full suite not rerun); Rust 196 passed / 1 ignored; Android host 94 passed / 1 skipped / 0 failed. No APK, instrumentation or device execution. Evidence: [verification](<reviews/VERIFICATION.md>).

**Build, dependency and test cleanup, audit T13 (2026-10-27):** code `3352354`, graph `f0b1e2b`. Missing-keystore release fallback explicitly warns instead of silently selecting the debug key; no APK was built or signed. Removed unused direct timezone/html/synchronized/open_filex declarations without surviving-version churn (timezone/synchronized remain transitive); Cupertino icons stay because live font references need them. Removed obsolete ProGuard keeps and stale network/casing NOTICE prose while retaining JNI/UniFFI rules and the complete Go resampling attribution/license. Collection worker checks use caller-order probes with synchronous negative controls instead of machine-speed-dependent tick counts; raw timing measurements and parity assertions remain, and two touched length checks use hasLength. Two orphan helpers, one empty test and obsolete lyric-channel mock arms are gone. TEST-101 stays open for source-coupled leftovers; no full dead-code sweep claim. Required dependency/test reviews PASS. Analysis clean; full serial Flutter 1,800 passed / 3 skipped / 0 failed; Android host 94 passed / 1 skipped / 0 failed across 20 suites. Existing Gradle/AGP/Kotlin deprecations remain. Rust source unchanged (NOTICE only); Rust checks, instrumentation and device execution not run. A caller scheduling opportunity is not continuous responsiveness or device throughput. Evidence: [verification](<reviews/VERIFICATION.md>).

**Accessibility and large text, audit T12 (2026-10-27):** code `601fa81`, graph `168d11d`. Shared controls and header circles use 48dp targets; choice/playlist/editor semantics, track-specific Play/Pause and menu labels, named sliders with real values, queue Remove and mini-player Dismiss actions, live selection counts and screen-reader-safe Rewind are implemented. Large text gets icon-only compact header pills, scalable track numbers, wrapping queue actions, growing statistics dates, scrollable Auto scan options and a width-aware lyrics-share layout with a full-width toolbar and 48dp swatches. Setup, guide, search reveal, editor and lyric crossfade motion honour reduced motion. Real-theme chip/badge AA contrast assertions cover light and dark (>=4.5:1), not physical-display certification. UX and Flutter reviewers PASS after fix-only re-review. Verification: analysis clean; full serial Flutter 1,792 passed / 3 skipped / 5 failed from fixture expectations. Corrected-file reruns cover all failures (10 passed / 1 failed, then the final helper correction passed its 1-test file); full suite not re-run under the batch rule. The unrelated pre-existing hero timestamp overflow exposed by the picker fixture is tracked as open UX-245; the modal fixture explicitly isolates the page while asserting 2x modal text. The T11 playlist-grid removal already resolves UX-209; tablet/foldable UX-207 and agreed RTL/English-copy exclusions remain open/deferred. No Rust/Android source changed; no APK, instrumentation, emulator or physical TalkBack execution. Evidence: [verification](<reviews/VERIFICATION.md>).

**Visible UI defects, audit T11 (2026-10-27):** code `f0d2318`, graph `4b59361`. Deleting part of an album now drops only the deleted rows and rebuilds the footer; the metadata sheet cannot be dismissed mid-save; Home cancels a stale search debounce; a damaged cached spectrogram is deleted and regenerated instead of spinning; Playlists rebuilds after renames, covers and track edits; Backup Import is single-flight; setup tips clear the Next button and system Back steps through setup. Library search drops stale select-all/load results after a query change, failed pages wait for Retry instead of loading on scroll, hiding search clears its query, Queue keeps the failed filter with a retry action, and pick/scan/remove/rename/cover failures report `friendlyError` instead of escaping. Library -> Playlists is rows and offers Create when empty; tabs build lazily; the performance HUD clamps its drag; a failed selection action closes the selection bar before showing the message so the panel cannot cover it; artist credits prefer an exact full credit ("Tyler, The Creator") before the first name, and album lookups log their failures. flutter-dart-auditor and ux-auditor PASS with fix-only re-review of the final delta. Analysis clean; full serial Flutter 1,770 passed / 3 skipped / 0 failed, after the first run exposed two defects in the new tests (real file deletion outrunning the fake test clock, and the Retry row built only after the scroll extent grows), both fixed and the suite re-run. No Rust or Android source changed, so those checks were not required; no APK, instrumentation or device execution. Evidence: [verification](<reviews/VERIFICATION.md>).

**Scanning and cover-cache cost, audit T10 (2026-10-26):** code `2063adf`, graph `1578d99`. Covers share published-thumbnail SHA-256 names across local and SAF readers; validated warm pointers expire after 30 days, cache publication skips fsync while exports remain durable, typed unreadable tags skip whole-file copies, Ogg scans collect artwork with tags, and unchanged CUE headers stream without a temporary copy or fixed-prefix truncation. Full-scan CUE ownership requires usable rows; output repair reads blocks and only reencoded CUE splits use input seeking. Required performance/Rust safety reviews and fix-only follow-ups PASS. Analysis clean; full serial Flutter 1,757 passed / 3 skipped / 0 failed, affected files 23/23; Rust fmt/Clippy/workspace 196 passed / 1 ignored; final Android host 94 passed / 1 skipped / 0 failed, instrumentation sources compiled (not executed). Release host cold cover scans: 2k shared-cover tracks 6,891 -> 705 ms, 2,000 -> 1 cover files, payload including pointers 36,260,000 -> 166,130 bytes; 201 large-cover tracks 3,024 -> 1,439 ms, 201 -> 3 covers. Warm rescans were slightly slower (174 -> 203 ms / 21 -> 24 ms); the unoptimized large-art slowdown is recorded rather than hidden. Opus reads save 2,808,512 bytes per crafted 2 MiB-art fixture; interrupted 1 MiB output repair 1,742.626 -> 1.538 ms; late CUE extraction 4.267 -> 0.414 s with matching decoded PCM. These are synthetic single host observations, not Android throughput. Checks ran serially with bounded workers/heaps for the owner's RAM limit. Write-only lookup-summary removal remains T14. No APK, device execution or syscall profiling. Evidence: [verification](<reviews/VERIFICATION.md>) and [raw measurements](<reviews/T10_MEASUREMENTS.json>).

**Library query and rebuild cost, audit T9 (2026-10-25):** code `fcacc49`, graph `3604db1`. Schema 19 indexes `album_artist_norm` so artist pages and the Artists shelf stop scanning the library; a per-connection genre tag cache replaces the recursive CTE on every Genres page; the dead lookup-index read path is removed. Queue pages regroup once per page and build selection data only in selection mode, folder screens select cover inputs, Home selects and memoises the playlist feed, startup orientation runs in parallel, and the artist/page ground is built once per width with a per-input failure memo. Popular flushes listening stats once per selection. Collections schema 4 adds the `(track_key, playlist_id)` index and first-cover lookup resolves ordered chunks and stops early; Rust native pins follow both schema bumps. Reviews (code-optimization-auditor, data-integrity-auditor, then test-auditor on the harness fixes) PASS after correcting two compile errors and four fixtures. Analysis clean. Full Flutter run 1,754 passed / 3 skipped / 0 failed. Rust fmt/Clippy passed; Rust unit tests NOT RUN because this host has no C compiler and linking fails, reported as a gap. On a 20k-row host fixture artist queries measured 6.3x faster, genre pages 10x and lists 3x; PERF-301 and PERF-405 were rejected with their measurements. The write-only `library_lookup_summary` triggers are deferred to T10/T14. No APK, instrumentation or device execution. Exact evidence: `reviews/VERIFICATION.md`.

**Library correctness and file-access safety, audit T8 (2026-10-25):** code `3602d2c`, graph `95f2ef3`. Keyed album queries and explicit total-track Singles; NFC search-only schema 18 in Dart/Rust without changing identity keys; exact normalized genres; conservative duplicate identity/quality and tri-state deletion; source/explicit queue metadata and artist release chronology; local cover retries; serialized collection cleanup, fresh reloads and cancel/join clear semantics; resolved selection counts, current settings search, and lazy log rows. Reviews and fix re-reviews PASS. Analysis clean. Full Flutter run 1,744 passed / 1 failed / 3 skipped; the new UTC/local representation assertion was corrected and its file rerun 6/6. Rust fmt/Clippy passed; workspace run 189 passed / 1 failed / 1 ignored due to the stale shared row fixture, corrected native-library file rerun 19/19 (190 distinct substantive tests covered). Android host 78 passed / 1 skipped. Log initial mounted rows 500 -> 10 at 800x1200; mixed-height autoscroll regression and cancellation covered. DATA-002's unused shuffle remains T14; T9 performance work separate. No APK, instrumentation or device execution. Exact evidence and known first-run test-harness/fixture corrections: `reviews/VERIFICATION.md`.

_Last updated: 2026-10-27_

**Status:** Phases 1-8 and the requested local-player refinements are implemented.
Latest source validation passed. The signed ARM64-only side-by-side **build 168** includes
fetched `d4dff781` (glass slider fix), source `2a2ab3be`, all completed upstream ports and Batch 16 cleanup.
It retains **Sistrum Local** (`com.amwolfstein.sistrum.local`), the cream/green launcher icon
and the certificate used by build 167. Physical-device validation remains pending.
`c29daef` removes the About page credits, translators, special thanks, links and social sections
(with `url_launcher`) and the Search tab Recent list (app-state schema v5 drops its tables);
`flutter analyze` and the full `flutter test` run now pass in batch 1b.
Vision refinements V1-V4 captured; Phase 6 decisions recorded in `PHASE6_DECISIONS.md`.

**Lyrics parsing, audit T6 (2026-10-24):** code `e6276a6`, graph `081b011`. Untimed TTML (paragraphs without usable `begin`, or with only plain text) now shows plain lyrics on both the Dart parser and the native production path instead of raw XML markup. The writer-credit trailer is removed from the retained plain text by exact match of the popped credit (credit-regex scan only as fallback) instead of rebuilding plain text from timed lines, which duplicated chorus lines shared by timestamps; the Rust `with_credits` path had the same rebuild and was fixed for parity. Repeated LRC timestamps now replay the relative word timing per occurrence, anchored at the occurrence nearest the first word, instead of sharing unshifted absolute word times (the existing "repeated line and empty end tags" golden was updated). Crafted LRC expansion is bounded on both parsers: timestamps per line capped at 64, words per line at 256, and a cumulative expanded-output budget of 16,777,216 units (word counts plus UTF-16 text lengths) beyond the first occurrence; measured before the fix (release build): a ~47 KB line with 2,000 timestamps and 2,000 word tags expanded to 2,001 lines in 7.0 s and 2.6 GB RSS. OPT-PERF-004 rejected with a measurement: the `with_credits` TTML re-parse costs 0.6/1.7/5.2 ms at 100/500/2,000 lines (execute 3.9/9.8/33.5 ms), sub-millisecond for realistic files, and the passes intentionally differ in CDATA treatment. rust-safety-auditor and bug-hunter PASS (one P3 each on the plain-text trailer scan, fixed, re-reviews PASS). `flutter analyze`: No issues found. Full `flutter test`: 1,668 passed, 0 failed, 3 skipped. `check_rust_backend.sh`: formatting and Clippy PASS, full workspace tests PASS. Android checks NOT RUN (no Kotlin/Android source changes). No APK, instrumentation or device execution.

**Playback and visible UI bugs, audit T7 (2026-10-25):** code `10f9b23`, graph `c1db077`. Restored-session seeks and `skipToPrevious` restarts are no longer lost: `seek` publishes the position, stores it as the pending start while no source is ready, and runs the transport seek inside the source-change serializer under the play generation, and the loader consumes that pending position, so a seek that lands before or during preparation wins. Fire-and-forget transport callbacks (`play` on interruption end, sleep-timer `pause`, player completion) now report failures through the existing playback-error path instead of leaving an uncaught async error, and `_playIndex` reports failures raised after its own generation bump (last-track completion waiting on autoplay). An accepted Play bumps the generation before starting so a Pause delayed on AutoMix cleanup cannot win, and deleting a queued file after an explicit stop no longer revives that session. Visible UI: the mini player's dismissal latch clears on a null/different item or an observed pause→play but survives the frames where an asynchronous stop still reports playing (which previously rebuilt a dismissed `Dismissible`); the batch progress dialog owns its own route (removing it can never pop Songs/Settings), routes Back through the existing once-only cancel, cancels when removed externally and ignores stale completions; the Cache page shows an `ErrorCard` with Retry instead of an endless spinner. Data: artist Popular keeps per-ID random priorities for the page lifetime (stable across index refreshes, fresh on reopen, counts and the 20 cap unchanged), search honours `localLibraryEnabled` (no local hits and no index access when disabled, playlists still searchable), batch ReplayGain drops CUE virtual rows before its totals and logs false writes and exceptions, and legacy `http` covers are placeholders in `PlayerArtwork`/`playableFromLocal` (the widget already rejected every non-file scheme, so nothing was ever fetched). Native: `NativePlaybackFailure.kt` converts `LinkageError` only (cause preserved; ordinary exceptions and VM errors untouched) at the existing prepare/command/pump boundaries in `HiResPlayback`, `UsbDirectPlayback` and `UsbBitPerfectPlugin`; `UsbPcmSource` releases partially initialised JNI state and WavPack DSD construction closes its decoder handle when construction fails. Widget commands share one allow-list between the activity bridge and the receiver. `AudioService.onGetRoot` now validates the callback package against `PackageManager.getPackagesForUid(uid)` and permits only this app or Android-trusted controllers, failing closed; the owner chose that restriction, accepting that untrusted car/controller apps can no longer browse the queue, and the service stays exported. KT-001 rejected: the owner keeps `NativeReplayGainPolicy` for the planned Media3 port. Reviews: concurrency-auditor found two P2s in the new code (Play/Pause generation, seek persistence extending the transport lock), flutter-dart-auditor one P2 (stale-`playing` dismissal latch), kotlin-android-auditor one P3 (WavPack DSD handle cleanup); all fixed with fix-only PASS, and security-auditor PASS with the AndroidX `media:1.8.0` callback contract and API 24/Android 16 binder guards verified from the exact sources jar. `flutter analyze`: No issues found. Full `flutter test`: 1,700 passed, 0 failed, 3 skipped (10 failures in the first full run: six test-harness defects and the two real concurrency bugs plus a wall-clock assertion, all fixed). Android host checks: BUILD SUCCESSFUL with 79 app tests (1 skipped) and 7 audio_service tests passing, including the new `NativePlaybackFailureTest` (4), `PlayerWidgetCommandPolicyTest` (2) and `BrowserClientPolicyTest` (4); instrumentation sources compiled only. The SDK had no platform/build-tools/NDK, so those packages and the Gradle wrapper were installed with the owner's approval to run the checks. Rust checks NOT RUN (no Rust source changes). No APK, signing or device execution.

**Backup restore, settings restore and startup, audit T5 (2026-10-23):** code `ecbfd6df`, graph `06d6aada`. Crafted backups can no longer write outside the private playlist-cover folder: covers publish to versioned private paths, commit with the collection rows and roll back on failure; legacy JSON covers accept embedded data only. History fallback restore is atomic; settings restore keeps setup completion and the local library source, reports save failures and names partially applied categories. The download-era storage settings, SAF repair dialog, migration prompt and 2 s startup probe are removed (old settings and backups still import), and artist tag writing is pinned to joined. Export refuses backups the importer would reject; the metadata cap is 32 MiB in Dart and Rust, and collections export streams a database snapshot. Dead CSV/M3U import and native `parse_playlist`/`hash_file` jobs are removed; malformed setup drafts are discarded. Reviews and fix re-reviews PASS. `flutter analyze --no-pub`: No issues found. Full `flutter test --no-pub`: first run 1,654 passed, 2 failed, 3 skipped — both failures were the new malformed-draft setup test, which ran twice inside the SDK loop and mistook the determinate page-counter ring for a loading spinner; it now runs once and asserts the first page renders (file rerun 8/8). Final full run after all fixes: 1,656 passed, 0 failed, 3 skipped. `check_rust_backend.sh`: formatting and Clippy PASS; 187 passed, 0 failed, 1 ignored (191 before: the dead `parse_playlist`/`hash_file` tests were removed with DATA-101). `check_android.sh` (JDK 25): BUILD SUCCESSFUL. No APK, instrumentation or device execution.

**CUE, library identity and cover-cache safety, audit T4 (2026-10-23):** code `8232af13`, graph `d0ca1528`. CUE parsing rejects multi-file sheets and invalid/out-of-order timestamps; case-insensitive audio resolution avoids Unicode slicing, real #track filenames remain physical, and incremental scans re-read backing metadata. New library/cover keys use full SHA-256; scan publication retains existing same-source/path IDs and remaps keys transactionally, keeping collection/history/backup references compatible without a schema migration. Thumbnail-cache poison recovery discards interrupted state. Queued scans preserve active progress and pre-paused scans remain cancellable. USB completion flags use separate stable allocations and packet scheduling carries capacity excess. Snapshots skip unrepresentable rows without deleting them; log exports disclose retained path information. Required specialist/security reviews and verification-fix re-reviews PASS. `flutter analyze --no-pub`: No issues found. Full `flutter test --no-pub --reporter expanded`: 1,650 passed, 1 failed, 3 skipped; the failure exposed the artwork overlap-readback test's fixed 30 ms native-completion assumption. Replaced that wait with bounded completion/timer polling while retaining exact readback and idle assertions; test-auditor PASS, corrected file rerun 7 passed, 0 failed/skipped. Final `check_rust_backend.sh`: formatting and Clippy PASS; 191 passed, 0 failed, 1 ignored. Verification also caught a pre-paused scan registration deadlock, fixed and re-reviewed; the new CUE fixture was corrected to FLAC metadata probing rather than unsupported WAV duration probing. Android host script NOT RUN (no Kotlin/Android source changes). No APK, instrumentation/device execution, Miri or sanitizer run.

**Tag writing and metadata editor safety, audit T3 (2026-10-23):** code `4dcb1f9b`, graph `46d34cf3`. Only dirty fields are written; native MP3/M4A refusal preserves the original instead of remuxing unknown metadata away. SAF replacement verifies backup and rollback, retaining a recovery copy on failed restoration. ID3 text, frame boundaries, extended headers, unsynchronization and UTF-16 descriptions are corrected; WAV/AIFF, APE, MP4 and Ogg edits preserve retained metadata. Invalid replacement covers fail before publication; analysis caches compare modification times; cover snapshots use the shared schema version. Existing reference-aware pruning already handles old edited covers (DATA-307 rejected). Native path identities now match Dart for case and SAF CUE fragments, resolving the two parity failures carried from T2. Specialist re-reviews and the SAF security pass PASS. Analysis: `flutter analyze --no-pub` — No issues found. Full `flutter test --reporter expanded`: 1,646 passed, 2 failed, 3 skipped; corrected schema request expectation and reran both failing files against final sources (`library_cleanup_test.dart`, `metadata_write_safety_test.dart`): 12 passed, 0 failed/skipped, no unresolved failures. The full run overlapped the final preservation-guard edits; the isolated final-source rerun confirms the pre-FFmpeg guard. Final `check_rust_backend.sh`: fmt/Clippy PASS, 182 passed, 0 failed, 1 ignored; native/Dart path parity failures found during verification were fixed (case-sensitive paths and SAF fragments) and re-reviewed. `check_android.sh`: BUILD SUCCESSFUL, 72 passed, 0 failures/errors, 1 skipped. No APK, instrumentation or device execution.

**CUE delete and split safety, audit T2 (2026-10-23):** `76f2fb10` code, graph `772c6c83`. Deleting a CUE-backed row now only removes the DB row in all three paths (song menu, batch delete, album multi-select) through the shared `isCueBackedRow(path, format)` (virtual `#trackNN`, `.cue` path or `cue+*` format), so the sheet and its shared audio survive. Local virtual detection requires `\.cue#trackNN` (content URIs keep any trailing suffix), so a real file named `… #track1` stays deletable, and `stripCueTrackSuffix` never rewrites other paths. Splitting is guarded by a per-sheet in-flight set, returns `CueSplitResult(paths, failed)`, cleans failed outputs and dedupes repeated output names. Cover and SAF export failures are per-file and reported as partial success; the picked tree is matched to a library source by physical-path and removable-volume keys and rescanned, otherwise the snackbar says the tracks were saved outside the library. Also hides Copy/Edit on virtual rows, returns cancel from batch ReplayGain, rewrites the split confirm copy, and maps Rust CUE audio resolution errors to the stem fallback (SEC-201). Reviewers: data-integrity-auditor and test-auditor both PASS (the test pass was repeated after P3 cleanups in the new tests). PASS: `flutter analyze` clean; full Flutter suite `+1637 ~3` (1,637 passed, 3 skipped, 0 failed); `local_song_menu_actions_test.dart` 14/14 and the two timing-sensitive files together 15/15. `check_rust_backend.sh`: 93 passed, 2 failed, 1 ignored; both failures are pre-existing `crates/mobile` path-key fixture drift reproduced unchanged at `d015e7d9` in a clean worktree. NOT RUN: device, integration tests, APK (never built).

**SAF scan correctness, audit T1 (2026-10-23):** `46c4ea6a` code, graph `ed278a7d`. A provider error is no longer an empty folder: `querySafChildrenOrThrow` throws on `DocumentsContract.EXTRA_ERROR`, a zero-row listing cannot replace rows an indexed source already has (`safEmptyListingIsUntrusted`, plus `has_indexed_rows` from Dart for forced scans, which delete the resume files), incremental scans throw instead of emitting removals for an empty listing, and pruning waits for a non-empty listing. Incremental scans treat a zero timestamp as changed, reconcile changed CUE sheets by claiming or retaining their backing audio (a failed or empty sheet keeps its `#trackNN` rows instead of deleting them), remove the standalone row a CUE now owns, skip an unchanged resumed CUE per audio key and count it before totals, and the resumed checkpoint is pruned against the current listing. The picker retries READ|WRITE then READ, treats a grant without READ as no grant and returns an error instead of a tree it cannot keep (Dart shows a SnackBar); scan state moved to the `MainActivity` companion with a process-scoped `SafScanProgressStream` so a recreated Activity keeps reporting; removing a source releases its persisted grant once unused and never for the legacy download tree (T5 removes that flow). CUE identity keeps its anchored `#track\d+$` fragment, and only Windows drive paths fold case. Reviewers: kotlin-android-auditor, data-integrity-auditor and (file deletion/SAF) security-auditor all PASS with no findings after three rounds; the security pass also fixed the live relocated double-decodes (SEC-004's cited file is gone). PASS: `flutter analyze` clean; Android host unit tests `BUILD SUCCESSFUL` (JDK 25, installed user-local at `~/.local/share/jvm/jdk-25` because the machine default is 21 and the build pins Java 25); full Flutter suite `06:05 +1609 ~3` (1,609 passed, 3 skipped, 0 failed). During verification the removal path deadlocked when it raced the initial index load (it awaited the load to look up the folder); it now reads the source list, falling back to one storage read only when the index has not loaded, and three pre-existing `sistrum_artwork_glass_test` timing flakes (its 800 ms real-time decode budget under parallel load) were made deterministic by waiting up to 3 s; no test was skipped or disabled. The graph rebuild needed `--force`: graphify 0.9.72 extracts fewer symbols from the vendored `libusb.h` (357 -> 180), 217 nodes unrelated to this change. NOT RUN: device, integration tests, APK (never built).

**Local ARM64 build 168 (2026-10-21):** Owner paused the new audit and requested the latest branch build. Fetched `d4dff781`; release metadata source `2a2ab3be`, graph `686a463f`. Analysis clean; full Flutter 1,514 passed / 3 skipped before the version-only bump; signed release compilation and artifact audits PASS. VersionCode2168, ARM64-only Sistrum Local, cream/green icon and certificate matching167. APK 52,787,208 bytes, SHA256 `98c0ab17ef57b39870e24b654a1ad6be8883d7d09923a9a61c6ee5a2032cdecf`. Device NOT RUN. [Download](https://github.com/AMWolfstein/Private/raw/refs/heads/apk-local-arm64-168/%53%70%6F%74%69%46%4C%41%43-Local-168-arm64-v8a.apk); details in reviews/LOCAL_BUILD_168.md. This supersedes the earlier source-session note that its environment could not package an APK.

**English only (2026-10-23):** `b06602f` code, graph `6d8a8d4`. Owner request: English is the only language. Deleted 19 translation arb files (including the `pt_BR` rename made earlier today), the Indonesian widget strings (`values-in`) and the stale `supported_locales.dart`; Android `locale_config` lists only `en`. Setup has no language step (seven or eight pages instead of eight or nine; drafts below version 3 move later steps back by one so they resume on the same tip), Appearance and settings search have no Language option, and `AppSettings` no longer stores a locale (old saved and backed-up `locale` keys are ignored). `MaterialApp` is fixed to English. This closes UX-204, UX-221 and Codex FA-UI-001; RTL and translation findings are deferred in T12. PASS: analysis clean. Full suite `06:32 +1610 ~4 -2`: the two failures were tests that checked Indonesian copy (`playback_feedback_test`, `tutorial_copy_test`), rewritten for English; both files re-run `00:01 +4: All tests passed!`. NOT RUN: device.

**Brazilian locale code and snackbar durations (2026-10-23):** `23b1b46` code, graph `76d3226`. Owner decisions from the UI re-audit. UX-227: the "Português (Brasil)" translation is Brazilian (arquivo, você, tela, configurações) but was filed as `pt_PT`; it is now `pt_BR` (arb, supported locales, language list, Android `locale_config`), and `AppSettings.fromJson` maps a saved or backed-up `pt_PT` to `pt_BR` (`kRenamedLocales`). UX-238: snackbars still close within 3 s, but a request longer than the Material default keeps its time up to 8 s (restore restart hint 6 s, USB volume warning 8 s). UX-228 rejected (setup keeps the storage permission required); UX-234 (EQ gain mirrors in RTL) left for T12. Arabic is hidden from the language list because `filteredLocaleCodes` only lists languages that passed a 70% translation check; that list is stale (its generator `tool/check_translations.dart` is gone) and Arabic is about 23% translated. PASS: analysis clean, full suite `06:09 +1605 ~4: All tests passed!`. NOT RUN: device.

**Menu material and Popular play button (2026-10-22):** `649946b` code, graph `bc10cdd`. Owner report: song ⋯ menus on Songs, artist and album pages took 1-2 s to turn from blur into glass. Page menus staged their glass (opaque while flying, then lens refraction and tint faded in over the last 38% of the 320 ms open, reversed on close); under heavy frames that read as a slow switch. All `showSistrumContextMenu` menus now keep one material from the first frame to the last, as the player's artwork menus already did. Artist Popular rows use the song rows' outlined circular Play/Pause (`LocalSongPlayButton`, extracted from `LocalSongRow`). PASS: analysis clean. Full suite: 2 failures, both `sistrum_menu_motion_test` cases asserting the staged reveal (rewritten to assert glass from the first frame; file re-run `00:01 +3: All tests passed!`). NOT RUN: device.

**Detail header ground veil (2026-10-22):** `d9008c3` code, graph `30c7bc4`. Owner HUD on an artist page (full, Level 5, 48 frames): reads=2, build 6.2/12.1/14.5 ms, raster 21.4/28.1/42.8 ms, jank 81%. The artist header re-blurred its full-width photo on every scroll frame (`ImageFiltered`, sigma up to 18). `SistrumGroundVeil` now paints the page's existing ground (artwork + gradient, pre-blurred at the clarity sigma, 384 px wide) over the artwork with eased opacity: the artist header by collapse (then the surface fade as before), album and playlist covers by how far the cover has scrolled under the toolbar. Same gates as the old blur (liquid glass, motion); nothing until the ground is ready. At Level 5 the ground (sigma 6) is softer-looking than none but less blurred than the old peak; the surface fade covers most of that range. PASS: analysis clean. Full suite: 2 failures, the artist test that asserted the live blur (rewritten to assert the veil and no `ImageFiltered`) and the bottom-bar header-inset rebuild test (the album header read the top inset at header level; moved into the veil); both files re-run `00:15 +50: All tests passed!`. NOT RUN: device re-measure.

**Root route chrome batch (2026-10-22):** `fa09528` code, graph `6a31a2e`. A second `SistrumChromeBatch` above the router's navigator (in `MaterialApp.builder`) lets header controls on root routes (Settings and its subpages, also equalizer and statistics) share one key; tab pages keep joining the nearer shell batch. Controls keep 48 dp / 4 dp / 22 dp and the same glass. Host counts are unchanged (Settings 2, Appearance 4/5 on full; 1 and 2/3 on lite): the test renderer has no Impeller, so lens passes carry no key there, and with one member lite has nothing to merge. Expected on device: the back circle's two lens passes read once (about one read less per frame). PASS: analysis clean, full suite `05:35 +1602 ~4: All tests passed!`. NOT RUN: device re-measure.

**Appearance segmented reads (2026-10-22):** `43fc2d0` code, graph `bf43f49`. Owner HUD on Appearance after the search fix (full, Level 5): reads=6, raster 16.9/27.0/39.9 ms, jank 55%. The two `SistrumSegmentedControl` tracks were resting lenses on the plain page; they now keep the tint without a read (the pill stays touch-only liquid glass). Host count: rest 6 -> 4, scrolled 9 -> 5 (back circle, clarity preview panel, band). `sistrum_glass_level_test` counts one fewer blur. Full suite: 5 stale count failures in that file (fixed, file re-run 13/13) plus 3 in `sistrum_artwork_glass_test` (`ground never became ready`: its 800 ms real-time decode wait under parallel load; passes alone and in repeated combined runs, also without this change's code path). Affected 19 files re-run: `01:55 +307: All tests passed!`. NOT RUN: device re-measure.

**Settings search reads (2026-10-22):** `d9574c1` code, graph `48a6318`. Owner HUD on Settings (full, Level 5, 60 Hz): reads=9, raster 14.8/26.9/49.1 ms, jank 41.9%. The Settings and Logs search fields were liquid lenses scrolling inside page content; like Home and Songs they now keep the tint without a backdrop read (`samplesBackdrop: false`). Host count on Settings: 4 -> 2 reads (only the back circle remains, plus the band once scrolled). PASS: analysis clean, full suite `05:56 +1602 ~4: All tests passed!`. NOT RUN: device re-measure.

**Header controls (2026-10-22):** `be6d62c` code, graph `22fbd37`. Every pinned header except the player uses 48 dp controls 4 dp from the screen edge with 22 dp glyphs: the back (or selection Close) circle, one glass capsule for the page's icon and menu buttons (the Logs ⋯ menu and playlist actions now join it), and the profile photo at the trailing end, 8 dp after the capsule. The photo opens Settings, is a plain 48 dp photo outlined like the glass rim (no fill), shows on every page including selection mode, and hides on Settings and the pages Settings opens (`ShellNavigationService.settingsOpen`; tab pages keep it). The artist toolbar uses the shared leading width. Headers mirror in RTL (back at the start, photo at the end). PASS: analysis clean, full suite `06:00 +1602 ~4: All tests passed!`. NOT RUN: device.

**Sistrum 5.2.5 ports (2026-10-22):** Checked upstream `e0563ffa..9bf4c000` and ported U-401..U-412 in two batches (`reviews/UPSTREAM.md`): DSD/WavPack rows no longer fail a scan and invalid rows are skipped with previous entries kept; synced lyrics keep running while the app is inactive and late line timers catch up; FLAC-in-MP4 tag writes; Samsung SM-S711B Android 16 Skia fallback; hidden artwork-contrast readback and per-frame fast-scroller timers removed; RTL mirroring for shared Sistrum widgets with the transport kept LTR; Go to Album keeps the album already on top; the no-lyrics state stays above the controls; lyric wrapping is stable when lines activate; spectrogram PNG export. Analysis clean; batch A full suite passed, batch B's three failures were stale icon lookups, fixed and re-run. Android unit tests not run (no SDK here); device validation pending.

**Cover colours and artwork glass (2026-10-22):** One analysis per cover version replaces the three per-screen colour paths (Score seed, hue-bucket `sourceColor` with HSL tweaks, separate top-lightness decode): `analyzeCover` averages the whole image, bottom 20% and top 25% in CAM16-UCS from one 112 px decode plus the native quantizer's counts, with chroma ceilings over at least 10% of the area; `sistrumCoverColors` derives every role in HCT from the bottom edge (album/artist surface, player gradients, menus, lyrics card, home widget), never above the cover's chroma (floor 6, neutral below 6, cap 36), with AA on-colours and a Score accent kept only when harmonious. Results persist in the library DB's derived `cover_analysis` table (lazy, 4,000 rows). The player's menus, actions menu and details sheet, and album/artist header controls, draw from pre-blurred 384 px ground images through `sistrum_artwork_glass.frag` (refraction and dispersion on full Levels 2-5; the plain ground on lite/Level 1); no backdrop reads there, one material per overlay, no staged reveal, 6 MB budget. The shader loads and warms at start; the ⋯ menu keeps its collection lookup alive. Timeline spans: `Sistrum menu: open to first frame`, `Sistrum ground: player|page`, `Sistrum cover analysis`, `Sistrum artwork glass: prepare`; the HUD shows `ground=`. Host ground build ~13 ms warm (25 ms first) with the 112 px fixture. PASS: analysis clean, full suite `04:35 +1602 ~4`. NOT RUN: device, integration tests.

**Public chrome batch (2026-10-22):** reworks the shared reads onto the package's public API: one `LiquidGlassBatch` over the shell (package-allocated key, read with `LiquidGlassBatch.backdropIdOf`), opt-in `SistrumChromeMember`, and our own `SistrumBackdropLayer` pushing the key on Impeller only; no `src/` imports and no own ids. Lite chrome frost goes through that layer; `LiquidGlassLite` (blur 0, `_kRimFromBackdrop = false` in 5.0.0) paints only the rim. The band reads on its own under the controls; folding side buttons, moving/covered routes, page content and tab-navigator sheets stay out. Reads per frame in the shell, lite and full alike: 1 at rest, 2 with the band, 3 mid-fold. PASS: analysis clean; full suite `04:25 +1587 ~4`; new tests for paint order (every row composited before the first member), lens keys, sheet exclusion and route transitions. NOT RUN: device, integration tests.

**Shared chrome backdrop reads, sigma floor and measured Auto (2026-10-22):** `cb39d15` code, graph `bb6b95c`. Owner HUD runs (60 Hz) showed glass was all of the raster cost (off 5.0 ms avg; lite L1 14.4, L3 15.0, L5 20.3; full L5 29.6). The shell's `SistrumBackdropGroups` gives the persistent chrome two shared backdrop keys used by blur passes (`SistrumBackdropBlur`) and package lenses alike: surface (band, tab capsule, mini player) and controls (header leading circle and action capsule, bar side buttons); moving or covered routes read on their own. Before, on full: bar 1 read expanded / 5 collapsed, header circle 2 and capsule 2 (unbatched lens + blur), band 1; on lite: bar 1 / 3, circle 1, capsule 1, band 1. After, in the shell: 2 in total on either quality. Root routes (Settings, Appearance, About) keep their own reads. `kSistrumGlassLevels` never blurs below sigma 6. Auto samples p90 raster time after a 3 s warm-up (180 frames; >14 ms: full -> lite -> lite Level 1) and saves it per build under `sistrum_glass_auto_probe`. Developer options and the HUD add bar sampler and band blur A/B switches and "Measure Auto glass again"; the HUD starts top-left, drags, minimizes and shows `reads=N`.

PASS: analysis clean; full Flutter suite `04:38 +1585 ~4: All tests passed!`; new `sistrum_glass_auto_probe_test` (sampler, persistence, provider effects, host stepping full -> lite -> Level 1 from synthetic frame timings) and bar/header read counts from the layer tree (collapsed bar 3 -> 2 reads, header circle + capsule 2 -> 1), route-transition opt-out, HUD placement, drag, pill and tap-through. NOT RUN: integration tests and the device; APK build left to the owner's build agent.

**Glass quality, five clarity levels and performance HUD (2026-10-22):** `48ead6d` settings (A, C and D), `773d88d` level table (B), `fcbb391` HUD (E), `c5423d9` Songs search field without a backdrop read, graph `a81c746`. `glassQuality` (auto/lite/full/off) replaces "Always use blur effects": Auto = full on liquid-capable non-low-end devices, lite on other standard devices, off on low-end; explicit choices bypass the high-contrast block. `glassClarityLevel` 1-5 (Frosted, Soft, Balanced default, Clear, Crystal) is stored in app settings so backups carry it; `kSistrumGlassLevels` (`lib/theme/sistrum_glass_levels.dart`) holds tint, blur sigma (10/8/6/4/2), dispersion (0/0/0.5/1/1.32), clear-fill mix, context-menu opacity and the adaptive bar's light fill. Rendering: off = opaque; Level 1 = grouped BackdropFilter + tint (+ LiquidGlassLite painted rim when outlines are on), never a lens; Levels 2-5 = lenses on full + Impeller, otherwise the same blur + lite rim. Touch-only thumbs and segment pills stay lenses under lite (not Level 1, not off); the tab bar's floating layout, header lenses and the bar's adaptive sampler need full above Level 1. The header band blur and bar fill read the table. Appearance has a quality segmented control and a 5-stop named slider (preview-only drag, one persisted commit); the Crystal note shows only on full. Startup migrates the old clarity double and blur flag once (<=0.2 -> off/3; (0.2,0.35] 1; (0.35,0.55] 2; (0.55,0.7] 3; (0.7,0.9) 4; >=0.9 5; forced blur -> full) and deletes them; old backups restore through the same mapping. The HUD (7 taps on About's version, Developer options) shows avg/p90/p99 build and raster ms, jank against the real refresh rate and the glass settings, with Reset and Copy; off it is not mounted and registers no timings callback.

PASS: analysis clean; full Flutter suite `06:10 +1564 ~4: All tests passed!`; new `sistrum_glass_migration_test` (every mapping row, startup migration, corrupt blob, old and new backups), `sistrum_performance_hud_test` (stats, reveal, HUD off = no callback, Copy) and level/quality cases in `sistrum_glass_level_test`, `appearance_settings_test`, `appearance_clarity_drag_test`, `app_switch_glass_test`, `sistrum_floating_header_test`. Integration tests updated to levels but NOT RUN (need a device). APK NOT BUILT here (another agent builds it). Device measurement NOT RUN.

**Floating glass headers and adaptive bar (2026-10-22):** `a844497` headers, `9e597b9` bottom bar, graph `eb417e2`. `AppSliverHeader` (21 pages incl. settings), the album toolbar and the artist toolbar are transparent unless the level is flat or contrast blocks glass (then the old opaque bar). New `sistrum_floating_header.dart`: glass back circle, runs of `IconButton` actions in one capsule (the Home avatar keeps its circle), and a `LiquidGlassScrollEdge` backing that fades in only when content is scrolled under (liquid: blur 5, 72% page tint; frosted, reduced motion or no shader filters: no blur, 94% tint and no lens). Status-bar style is explicit (a transparent AppBar estimates as dark); title/leading/action insets are directional. The album toolbar over its cover takes its palette and status icons from the cover's top-quarter CIE L* (`CoverPalette.topLightness`, one 112px decode, cached), otherwise the page. LiquidGlassAppBar was rejected (single capsule, no sliver collapse, no RTL). Bottom bar: where liquid chrome is allowed the shell wraps its pages in one `LiquidGlassView` (batch/realtime off) with an invisible `LiquidGlassAdaptiveArea` over the bar footprint; its verdict drives the bar theme and navigation-bar icons (artist page override still wins) and lets light bar glass drop its 50% floor (navigation 0.49→~0.28, mini player 0.70→~0.41). Sampling is held by `LiquidGlassAdaptivityController`: zero captures at rest, 6 Hz while scrolling, one look on scroll end, +400 ms and on visible-page change. Headers do not sample: inside the page they would read their own glass and band. Light-mode "solid white" bar was a style choice (≥50% white floor, `strongTint` skips the clarity clear-fill) over white pages, not a setting or device fallback.

PASS: analysis clean; full Flutter suite `06:11 +1545 ~4: All tests passed!`; new `sistrum_floating_header_test` (glass/frosted/reduced-motion/no-shader/flat/high-contrast headers, back pops, title collapses, RTL, status bar, album artwork verdict) and `sistrum_chrome_adaptivity_test` (no view when gated, held at rest, live while scrolling, single looks, page-change look, override precedence, clear light tint); `sistrum_tab_pill_motion_test` now counts the bar capsule's lens. No golden tests exist. APK NOT BUILT: `scripts/build_android.sh` stops with "No Android SDK found"; dl.google.com is refused by the network policy, and NDK, Rust Android target, cargo-ndk and `android/key.properties` are absent. Device look/readability/smoothness NOT RUN.

**Liquid-glass controls (2026-10-21):** `d42fef0` switch, `449ba4c` sliders, `9fa1948` tab bar. Shared `SistrumGlassThumb`: a painted pill at rest (no lens, ticker or capture) swapped for one `LiquidGlassMotionPill` (liquid_glass_easy 5.0.0) from touch-down until the contraction hides the glass. Gate (`sistrumGlassThumbsEnabled`): shader filters, liquid tier, clarity > 0.2, motion and contrast permitted, enabled control; latched per touch. AppSwitch keeps its gestures/InkWell/semantics/RTL/0.5 disabled opacity and onChanged rules (credit upstream Sistrum `9247b99a^`; NativeGlassMetrics not reintroduced). `SistrumSlider` replaces `Slider` at the five settings sliders with identical arguments; with glass open its resting thumb is a white pill (owner option i: Material thumb remains the fallback). Horizontal `SistrumLevelSlider` (EQ pre-amp) gets the glass knob; vertical faders, seek and volume unchanged. Tab pill: drag squash/stretch via `LiquidGlassLensMotion` (12% cap); light resting pill tuned to the Apple Music reference (4% fill, shadow outside the fill; measured ~4% vs reference ~3.5-4% darkening). New `sistrumShaderFiltersSupportedProvider` makes the shader gate testable.

PASS: analysis clean; full Flutter suite `05:33 +1532 ~4: All tests passed!`; new `app_switch_glass_test`, `sistrum_slider_glass_test` (drawn thumb equals Slider's painted centre, LTR/RTL, discrete/continuous), `sistrum_tab_pill_motion_test`. Graph refreshed in `e9cdfe2` (it already included the slider and tab-pill sources from the working tree; later refreshes had no topology changes). APK NOT BUILT (network policy blocks `dl.google.com`; Android SDK/NDK, JDK 25, signing key absent). Device look/smoothness NOT RUN.

**Glass clarity drag preview (2026-10-21):** `d6d467c` makes the Appearance clarity slider preview-only while dragging. It holds a local drag value; only the preview panel follows it, through a new optional `clarity` override on `SistrumGlassPanel`/`SistrumGlass`. Glass elsewhere (bottom bar, chrome, menus, glass preparation) keeps the committed provider value, so it no longer rebuilds per step or crosses the 0.2 lens/warm-up threshold mid-drag. Release saves once and updates the app in one step; when idle the slider follows the provider (resets, restores).

PASS: analysis clean; full Flutter suite `05:42 +1515 ~4: All tests passed!`; new `appearance_clarity_drag_test` (no provider write or outside rebuild during drag, preview follows the drag, one persisted commit, external changes update the idle slider). Graph `d89f518`. APK NOT BUILT: `dl.google.com` is blocked by this environment's network policy and the Android SDK/NDK, JDK 25 and `android/key.properties` are absent. Device check NOT RUN.

**Glass clarity slider jank (2026-10-21):** `a935e65` moves glass clarity and outlines out of the `SistrumTheme` ThemeExtension into `sistrumGlassClarityProvider`/`sistrumGlassOutlinesProvider`. `SistrumThemeWrapper` selects only accent, system font and theme mode, so a slider tick no longer rebuilds both ThemeData objects, runs MaterialApp's 300ms theme lerp or rebuilds every `Theme.of` dependent. The Appearance page and custom font tile select their fields. The clarity preview and slider, and the bottom-bar mini player, have their own repaint boundaries (the tab bar and side capsules already had them). No visual values changed; persist:false while dragging, saved on drag end.

PASS: analysis clean; full Flutter suite `05:52 +1513 ~4: All tests passed!`; new `sistrum_glass_theme_isolation_test` build-counter test. Integration tests updated but NOT RUN (need a device). Graph `de9edcd`. APK NOT BUILT: this container has no Android SDK, NDK 30.0.16248370, Rust `aarch64-linux-android` target, cargo-ndk or `android/key.properties`. Device smoothness and glass appearance NOT RUN.

**Local ARM64 build 167 (2026-10-21):** Built from `c76237c6`, incorporating all completed upstream ports and Batch 16 cleanup. Version 5.1.1 / build 167, split versionCode 2167. Release flags: `SISTRUM_SIDE_BY_SIDE=true SISTRUM_RUST_ANDROID_ABIS=arm64-v8a flutter build apk --release --target-platform android-arm64 --split-per-abi --dart-define=GIT_COMMIT=c76237c6`.

APK `Sistrum-Local-167-arm64-v8a.apk`, 52,983,816 bytes; SHA-256 `8b5521fe78bbc1640675e26b1838776f370191c440a4288402d63efcc2b80639`. Package `com.amwolfstein.sistrum.local`, label Sistrum Local, minimum API 24 / target API 37, ARM64 only. All 17 native libraries are AArch64 ELF64 with at least 16KB LOAD alignment; ZIP 16KB alignment, CRC/backend audit, embedded source revision, cream icon background and absence of INTERNET permission verified. APK signature verifies and certificate matches build 166 (`b912cdc7e97b78a19aff3ac8398abc3b36251de2af67243e8a6da2870e15c7b3`). This is an update to the existing Local app and installs alongside the original package.

Analysis clean; full Flutter suite PASS: `03:16 +1513 ~3: All tests passed!`. Physical-device installation/playback NOT RUN. Initial build encountered a generated-plugin race when tests ran concurrently; after tests completed, release was rebuilt serially and passed. Do not run Flutter tests and APK builds concurrently in this checkout.

Download branch: `apk-local-arm64-167`, containing APK, README, SHA256SUMS and APK_DETAILS.json. [Download APK](https://github.com/AMWolfstein/Private/raw/refs/heads/apk-local-arm64-167/%53%70%6F%74%69%46%4C%41%43-Local-167-arm64-v8a.apk). Source → graph checkpoints: `c76237c6` → `a08624d2`; release docs checkpoint follows.

**Upstream port batch 16 (2026-10-21):** Retired unreachable Material Expressive UI and direct dependencies, download/provider/re-enrichment and iOS bridge APIs, dead Rust modules and unused settings/widgets/resources. Preserved offline metadata/lyrics editing, Audio Quality Analysis, CUE, local collections, playback and legacy backup/schema compatibility. Removed 70 unused l10n keys last; added native check script and test resource/timeout cleanup. Disabled selection actions retain explicit accessible state and 48px targets.

One reviewed source patch `ef8ba64d`; Graphify checkpoint recorded below. Cleanup follows FIX_PLAN Tier 3, not an upstream merge. Existing source-to-upstream mappings remain in UPSTREAM.md and prior PORT_EXECUTION checkpoints.

PASS: analysis clean; Flutter 1513 passed / 3 skipped / zero failures (02:09); Android unit 55 passed / 1 skipped; Rust fmt/Clippy PASS, 165 passed / 1 ignored.
Graph 331ab3d0, source ef8ba64d: 22,436 unique nodes / 42,940 valid links; synchronized, existing vendor extraction warnings remain.
No APK; Native unit checks and Rust fmt/Clippy/tests pass; regenerated host UniFFI bindings. Instrumentation sources compile, but device execution is NOT RUN. Paging regression passes 10/10. Test-only APIs and their obsolete cases were retired; retained Sistrum fixtures were adapted, not skipped. DEAD-806 remains partially open for legacy bookmark/path compatibility; DEAD-702 and unrelated DATA-501/KT-202 remain outside this batch. NativeReplayGainPolicy, MANAGE_EXTERNAL_STORAGE, live skeleton/ErrorCard/artist artwork, canonical ISRC helper and haptics SAF jobs retained. Atomic SAF helper retained per plan. No APK or runtime performance claim. material_ui remains an existing transitive dependency of retained go_router 18.0.2; no production material_ui imports/delegate remain. Replacing the router to remove that transitive dependency is outside this cleanup and needs a separate architectural decision. Next: none in PORT_PLAN; physical-device verification and separately approved remaining review fixes.

**Upstream port batch 15 (2026-10-21):** Refreshed upstream main remains e0563ffa. Compared all shared Pub declarations and overrides, resolved shared Cargo versions through both workspaces, and checked Flutter/Gradle/Android toolchain pins. No retained dependency version changes are available; no manifest or lockfile changes required.

Comparison-only checkpoint. Evidence: reviews/upstream-v5.2.0-dependencies.json; upstream e0563ffad6df9f01d3e73e6099f74417422374de. Source remains batch 14.

REUSED batch 14 verification for identical source; no redundant test execution in documentation-only batch 15. PASS: analysis clean; Flutter 1775 passed / 3 skipped / zero failures (04:18); Kotlin checks NOT RUN (no Kotlin source changes); Rust script NOT RUN (no Rust source changes).
Graph 53a17a8e, source 822a4656: 23,988 unique nodes / 46,040 valid links; synchronized, existing vendor extraction warnings remain.
No APK; 33 shared runtime packages, eight development packages, one common override and 20 shared workspace Cargo dependencies have matching versions; direct mobile workspace declarations resolve to the same roxmltree/rusqlite versions. Local-only crate has no equivalent upstream path. Upstream-only network, service, iOS and branding dependencies rejected. No dependency additions or APK. Next: batch 16 (one reviewed dead-code patch and final compatibility report).

**Upstream port batch 14 (2026-10-21):** PLAY-001..004 and U-311 adapt Immersive cover proportions/fade and a shared artwork/title swipe scope, retain the background across rotation, label the lyrics-size control and match queue swipe corners. Separate inset/full-bleed artwork keys and bounded ownership prevent rotation/rapid-view conflicts; queue-index selection avoids transport rebuilds on clock updates.

U-311 upstream `05a56133` → source `3dfa8b73` → graph `140ecef1`; lint `45c40118` → `9f62788e`; fixtures `5fd4892a` → `72145734`; ownership/subscription correction `822a4656` → `3c9fe836`, labels `53a17a8e`. PLAY-003 behavior also present in upstream befcd2ad; adapted using Semantics around the installed Flutter Slider.

PASS: analysis clean; Flutter 1775 passed / 3 skipped / zero failures (04:18); Kotlin checks NOT RUN (no Kotlin source changes); Rust script NOT RUN (no Rust source changes).
Graph 53a17a8e, source 822a4656: 23,988 unique nodes / 46,040 valid links; synchronized, existing vendor extraction warnings remain.
No APK; Normal remains default; persisted Immersive and landscape two-column behavior retained. Existing backdrop saturation and full-bleed Hero gating already match useful upstream behavior. Focused regressions caught and fixed GlobalKey ownership and clock-rebuild defects; ten corrected regressions pass. Transparent foreground artwork gesture region intentionally receives Immersive drags. Physical side-by-side visuals NOT RUN. No engine/dependencies/native changes, user-music writes or APK. Next: batch 15 (shared dependency comparison against refreshed upstream main).

**Upstream port batch 13 (2026-10-21):** HOME-001..008 adapt the local editorial feed: aspect-preserving indexed artwork with embedded fallback, cached shelves across scans, pull-to-refresh, guided empty/retry states and loading skeletons; localized dates, explicit labels and responsive themed cards; stable identities and Home reselect scrolling. Removed two unused Home parts and the unreachable branding intro.

Source `0d9dbf9c`, lint correction `504a38df` → graph `4b4fe09f`; cached-refresh fixture `f5ec3973` and hydration guard `c4e9e536` → graph `8ad07efd`. Compared upstream Home sizing/skeleton patterns at e0563ffa.

PASS: analysis clean; Flutter 1771 passed / 3 skipped / zero failures (04:18); Kotlin checks NOT RUN (no Kotlin source changes); Rust script NOT RUN (no Rust source changes).
Graph 8ad07efd, source c4e9e536: 23,983 unique nodes / 46,028 valid links; synchronized, existing vendor extraction warnings remain.
No APK; Recently Added ordering and release-tag-only Latest Releases queries unchanged. Optional long-press menus omitted; existing local detail navigation retained. Initial tests exposed viewport assumptions and missing standalone Intl date initialization, corrected before final checks. No music-file writes/dependencies/native changes or APK. Home same-path image invalidation remains with existing metadata/cache ownership. Tablet/device visual comparisons NOT RUN. Next: batch 14 (PLAY-001..004 and U-311).

**Upstream port batch 12 (2026-10-21):** MORN-013..016 unify effective collection artwork, use tonal Loved/playlist actions with feedback, fit short-screen covers, and improve Sistrum contrast and segmented touch targets.

Source `ce2538bf` → graph `5c2bdc49`; header fixture correction `8477c4bc` → final graph checkpoint. MORN-015 was already implemented by U-210 `c2f38c86` in batch 6.

PASS: analysis clean; Flutter 1769 passed / 3 skipped / zero failures (04:17); Kotlin checks NOT RUN (no Kotlin source changes); Rust script NOT RUN (no Rust source changes).
Graph 4bb91e88, source 8477c4bc: 23,970 unique nodes / 46,006 valid links; synchronized, existing vendor extraction warnings remain.
No APK; Ten light/dark artwork, feedback, contrast and accessibility regressions pass. Initial fixture lookup failures corrected to inspect the configured header before sliver flattening. No native/dependency/schema changes or music-file writes. Physical visual checks NOT RUN. Next: batch 13 (HOME-001..008; FIX_PLAN M7–M9).

**Upstream port batch 11 (2026-10-20):** MORN-006..012 adapt local album metadata and artist presentation: genre/year metadata, localized footer duration, first-playable Play-all, ReplayGain section labeling; matching artist controls, slot-specific placeholders, 280px collapse threshold, compact Popular rows and responsive album cards with year/local track counts and explicit single badges.

Source `df09d3ea` → graph `496dd75b`; shelf lint correction `2a6ea366` → `d1dd2638`; CUE-fixture real-song identity correction `b1fd7886` → `ff70d508`. Upstream-latest artist card/row patterns inspected at e0563ffa; adapted to retained local data and menus.

PASS: analysis clean; Flutter 1759 passed / 3 skipped / zero failures (04:13); Kotlin checks NOT RUN (no Kotlin source changes); Rust script NOT RUN (no Rust source changes).
Graph ff70d508, source 2a6ea366: 23,960 unique nodes / 45,975 valid links; synchronized, existing vendor extraction warnings remain.
No APK; Retained playback regressions now begin with a virtual CUE row and compact release-date metadata, covering both themes; first real-song identity remains explicit in later fixture checks. Artist visual/device checks NOT RUN. Single badges require explicit total-track tags=1. No EP type exists in the local browse model/database, so EP badges are omitted rather than inferred from file counts; EPs remain under Albums. No dependencies, schemas, music-file writes, native changes or APK. Next: batch 12 (MORN-013..016; FIX_PLAN M5+M6).

**Upstream port batch 10 (2026-10-20):** MORN-001..005 and MORN-017 align retained collection UI behavior: album selection owns the toolbar and hides playback actions; playlist/Loved use shared circular toolbar controls and collapse titles; hydration shows skeletons instead of empty flashes; current rows pause/resume without queue restart. Artist/album loading/error/empty presentation now uses retained Sistrum primitives and hides an empty Popular heading.

Source `bc983981` → graph `afcb349a`; fixture duration `b55043ba` → `36cdf5d4`; hydration fixture isolation `b602dfb3` → `de2c48ba`, duplicate override correction `ad7e26eb` → `d6b8c566`. Upstream-latest collection patterns inspected at e0563ffa; existing offline behavior retained.

PASS: analysis clean; Flutter 1759 passed / 3 skipped / zero failures (04:13); Kotlin checks NOT RUN (no Kotlin source changes); Rust script NOT RUN (no Rust source changes).
Graph d6b8c566, source ad7e26eb: 23,954 unique nodes / 45,967 valid links; synchronized, existing vendor extraction warnings remain.
No APK; Six new light/dark collection-state regressions cover selection exit, hydration and current-row toggling. Initial fixture failures were missing duration and duplicate provider setup; corrected before final verification. No dependencies, schemas, music-file writes, native changes or APK. Physical visual checks NOT RUN. Next: batch 11 (MORN-006..012; FIX_PLAN M3+M4).

**Upstream port batch 9 (2026-10-20):** U-301 adds the owner-selected optional per-player Android equalizer: 5/10/15/31 bands, tone/preamp/balance, headroom, limiter/compressor, local presets and bounded JSON import/share. A Sistrum-only editor and player/settings menu routes use retained grouped controls. Audio-info now reports EQ/bypass/native errors. Existing playback transport and direct/exclusive output remain intact.

U-301 source `8e05cbbf` → graph `babdbbbe` (ecf594aa + 68c739df); installed picker/API and bounded stream import correction `892eb173` → `5c602c59`; scrolled-control test fixture `c7924c53` → final graph checkpoint (see history).

PASS: analysis clean; Flutter 1753 passed / 3 skipped / zero failures (04:16); Android unit 62 passed / 1 skipped; Rust script NOT RUN (no Rust source changes).
Graph fd1a520b, source 892eb173: 23,940 unique nodes / 45,919 valid links; synchronized, existing vendor extraction warnings remain.
No APK; No dependencies/schema changes, user-music writes, Darwin backend or engine replacement. EQ defaults off and native failures are visible; direct/exclusive output bypass is covered by mocked transport tests. Physical sound/driver support and share/picker targets NOT RUN. Initial Dart/native check failures were installed picker/theme API mismatches, fixed before final verification; focused widget fixtures now settle scrolling before interaction. Model/preset/native-payload/transport/input-boundary tests imported or added. No APK. Next: batch 10 (MORN-001..005 and MORN-017; FIX_PLAN M1+M2).

**Upstream port batch 8 (2026-10-20):** U-304 adds local Rewind highlights and seasonal invitations using recorded listening statistics and Sistrum surfaces. U-305 adds pinned Unicode/month section headers and adaptive fast scrolling without changing the dedicated Songs/category layout or bounded paging. U-307 adapts compact launcher-player sizing, preserving existing controls/themes. U-312 bounds restoration checks, virtualizes Settings search, limits logo decoding, avoids redundant static contrast readbacks and scopes pinch updates to the grid.

Source → graph: U-304 `f4fb6794` → `39f9bf4a`; U-305 `6052f9ea` → `ef111d26` (includes U-209 cached locale formatters and U-312 pinned lists); U-307 `2c9c0305` → `e51d221c`; U-312 `c49d7af9` → `c05701ff`. Compatibility fixes `1c589407` → `4f5bc88d`; Rewind header/offline fixture fix `c3d79e0d` → final graph checkpoint (see history).

PASS: analysis clean; Flutter 1739 passed / 3 skipped / zero failures (04:10); Android unit 62 passed / 1 skipped; Rust script NOT RUN (no Rust source changes).
Graph 9020a7aa, source c3d79e0d: 23,813 unique nodes / 45,709 valid links; synchronized, existing vendor extraction warnings remain.
No APK; No dependency/schema changes or user-owned music writes. Rewind share targets and launcher resizing on physical devices NOT RUN. Initial analysis mismatches corrected using retained APIs; initial Flutter failures caught an unbounded close control and an upstream remote-source fixture assumption, both corrected before final checks. No runtime speedup measurement. Android widget visual redesign/preview intentionally excluded. Next: batch 9 (U-301 equalizer only).

**Upstream port batch 7 (2026-10-20):** U-308 completes local lyric quote cards, menu/long-press entry points, on-demand document reads and stale-share guards, restyled using retained Sistrum controls. Compatible held-word glow honors reduced motion and a bounded fade window, preserving settled/background ticker suspension. U-302 adds optional local music haptics, stable SAF identity and owned decoder jobs, transport synchronization, basic-motor support and bounded sensitivity/strength settings.

Source → graph: U-308 `d83068e6` → `9ae8c833` (78a5e078/2782b1f7); U-302 `df164fb1` → `ba844ef0` (11c6cf99/2455cabc/9acaa760). Follow-ups: artwork guard lint `b02895b0` → `1bb926e3`; Sistrum selection fixture `a9433d82` → `6bb22e86`; virtualized-card assertion `de546bd7` → `e0fd4bbe`.

PASS: analysis clean; Flutter 1692 passed / 3 skipped / zero failures (03:55); Android unit 61 passed / 1 skipped; Rust script NOT RUN (no Rust source changes).
Graph e0fd4bbe, source b02895b0: 23,480 unique nodes / 45,224 valid links; synchronized, existing vendor extraction warnings remain.
No APK; No dependencies/schema changes or user-music writes. Music haptics defaults off; physical motor sensation/timing and OS share targets NOT RUN. Android VIBRATE permission is the only permission added. Initial quote-limit fixture assumed all rows remained visible; corrected to reveal rows, assert 5/5 and scope preview checks to LyricsShareCard before final verification. New card preserves local artwork policy; no network provider restored. Next: batch 8 (U-304, U-305, U-307, U-312).

**Upstream port batch 6 (2026-10-20):** U-210 fits collection covers to short screens. U-217 adds release-triggered upward mini-player opening while keeping horizontal dismissal. U-218 adds bounded normalization pre-amp and Track/Album gain, with one cached tag read and live settings changes. U-303 adds a tappable quality badge and Sistrum audio-info sheet with read-only Android route facts, current gain/rate/direct state, local analysis and copied reports.

Source → graph: U-210 `c2f38c86` → `e0f9ba6d` (d28e3f65); U-217 `8a9f6091` → `53b473f0` (37162363); U-218 `0d126507` → `ae93ce55` (9eea6a1a); U-303 `bd8f88a6` → `44cbd9e8` (40f65d3a plus U-209 acbc614f number-pattern reuse). Fixture correction `8b7adfe6` → graph checkpoint (see history); initial imported sheet tests lacked ProviderScope, corrected before final verification.

PASS: analysis clean; Flutter 1670 passed / 3 skipped / zero failures (03:59); Android unit 61 passed / 1 skipped; Rust script NOT RUN (no Rust source changes).
Graph 1735a8c3, source 8b7adfe6: 23,304 unique nodes / 44,944 valid links; synchronized, existing vendor extraction warnings remain.
No APK; No dependencies, schema or user-music writes added. Native route support varies by device; actual playback/GPU/route behavior needs device checks. U-303 standalone HiResCheckCard depends on absent services/online wrappers and is excluded; existing AudioAnalysisCard retained. Audio-info EQ reporting is pending U-301 batch 9. Next: batch 7 (U-308, U-302).

**Upstream port batch 5 (2026-10-20; continued MEDIUM preference):** U-214
`10c04f7a` gates local Android startup channels on Activity attachment; U-215 `fa838caa`
applies the existing renderer rules before shared engine creation and adds the scoped
Android 15 Xiaomi workaround. Minimal Application registration and vendor patch documented;
no crash reporter or playback replacement. U-208 Material-only slider hunk rejected.
U-209 `ba751b35` / `2c4ce3ff` reuse existing Dart lyric-alignment and Rust credit patterns.
Removed online/download/history hunks rejected; missing audio-info and queue-section
formatter hunks deferred to their scheduled batches 6/8. Graph `11d8f750` synchronized
from `2c4ce3ff` (23,147 nodes / 44,693 links). PASS: analysis clean; full Flutter 1,659 passed / 3 skipped / zero failures (4m02s); Rust fmt/Clippy clean, 231 passed / 1 ignored; Android unit 61 passed / 1 skipped (1m06s).
No APK, dependency/schema changes or physical-device validation. Next: batch 6 only
(U-210/U-303/U-217/U-218); KT-202 remains open.

**Upstream port batch 4 (2026-10-20; requested MEDIUM):** U-205 `6e44c6be` reports
Android output failures without advancing the queue and supports retry; U-216 `95e2b158`
notifies open players when a same-ID snapshot gains duration/artwork/metadata. U-206 targets
the legacy Material fallback and is not imported: retained Sistrum title/swipe behavior
already avoids the outgoing-title stack. U-207 `d0818d7a` resolves verified SAF parents and propagates requested
LRC write failures; excluded online re-enrichment/download tests remain absent. Current
engine, UI and vendored descriptor patch retained. Graph checkpoints `a95ffcf6`, `4c66e5e7`,
`a85b4965`; final graph 23,112 nodes / 44,630 links. No dependency/schema/Rust source changes.
Batch 4 verification: PASS: analysis clean; full Flutter 1,657 passed / 3 skipped / zero failures (4m10s); Android unit 59 passed / 1 skipped; changed plugin and instrumentation Kotlin/Java compiled (1m58s). No APK. Next is port batch 5.

**Upstream port batch 3 (2026-10-20):** U-203 `e70ae974` recovers missing local album
artwork in headers/grids, retaining Sistrum controls and local images. U-212 `1d8e8f76`
shares aligned ID3 picture parsing, safely strips recognized-image NUL padding and repairs
app-owned cached previews; extension hunks excluded. U-213 `d256e0c7` extends existing
embedded artwork recovery to filesystem playback without any online fetching. U-204
`a41d3d4e` waits for audible progress/alignment before effect handoff and renders enough
input for faster effects; current engine, fallback and cancellation retained. Each source
commit has its own Graphify checkpoint (last `de32a041`; 23,093 nodes / 44,593 links).
Batch 3 verification: PASS: analysis clean; full Flutter 1,644 passed / 3 skipped / zero failures (3m55s); Rust fmt/Clippy clean, 231 passed / 1 ignored. No APK. Next is port batch 4.

**Upstream port batch 2 (2026-10-20):** U-202 `0f51f5d0` adapts `3dc2d690` to
preserve integer FLAC samples in the existing exact PCM output paths, bypassing vendor
extractors that may reduce precision. Statically linked libFLAC 1.5.0 is checksum-pinned;
its license and byte-precision/seek/truncation tests are included. No player-engine migration.
U-201b `e58217c8` has only removed-network production changes, even in local provider files;
local native cancellation already exists, so none imported. Optional `931b1091` importance
diagnostics are unnecessary for U-201. KT-202 remains open: scan recovery does not fix
incremental CUE duplicates. Graph `6361145f` synchronized; WIP patch removed after review.
Verification: PASS: analysis clean; full Flutter 1,629 passed / 3 skipped / zero failures (4m02s); Android unit 59 passed / 1 skipped; native host CTest 1/1 passed; ARM64 JNI/library build passed. No APK built. Next is port batch 3.

**Upstream port batch 1b (2026-10-20):** U-103b ports lyric spring scrolling (`91add520`,
code `f10f45f6`) and lyric-only performance improvements (`7600c169`, code `81869c48`):
indexed overlapping voices, cached prefix geometry, bounded/deferred long-document row
measurement, stopped subscriptions/timers while hidden or backgrounded and stopped completed
word tickers. Keeps quick scrubbing, reduced motion, manual-scroll ownership and the existing
single-file lyric widget. U-308 is partial: display-end estimates, held overlap focus and
backing-vocal drop-in from `78a5e078` are present; share cards, sharing entry points,
provider work and glow styling remain pending. No Material-only UI or branding ports.
U-104 dominant cover colors (`913faaa`) and U-201 scan recovery (`e8cff13`) are validated;
`f34ead84` fixes the latter's nullable subtitle lint. Analysis is clean; full Flutter suite
passes **1,629 tests, 3 skipped**. Android unit tests pass **59, 1 skipped**, including both
scan exit-info tests. No APK built. Graph refreshed and validated; next is port batch 2.

**Upstream port batch 1 (2026-10-20):** U-001 per-field tag separators (`5393d1d`: artist,
album artist, composer and genre separators applied on Edit Metadata saves through the Rust
writers and the FFmpeg fallback; Local Library > Tag separators; backups round-trip),
U-101 AutoMix advancing-audio wait (`a5bc4a8`), U-102 adjacent-title cache (`051ff44`) and
U-103 lyric segment geometry cache (`940fd79`). `flutter analyze` clean, Rust backend check
passes; full `flutter test` has only the accepted `file_stat_boundary_test` failure plus the
pre-existing `models_and_utils_test` app-state v4 expectation (database is now v5).

**Review-agent system (2026-10-19):** Adds a quota-bounded review setup without changing app
source: `reviews/PROTOCOL.md` (shared rules), `reviews/` state files, 14 read-only reviewer
agents plus `review-fixer` in `.claude/agents/`, `/review` and `/audit` skills, and
`scripts/review_scope.sh` for model-free scope, reviewer routing and graph freshness. No code
review has run yet; baseline analyze/test/Rust checks are logged in `reviews/VERIFICATION.md`.

**Song-menu actions and anchoring follow-up (2026-10-19, `6ac8efd`):** Restores the old local
track overflow actions in Songs, playlists/Loved Songs, albums, Genres and Artist Popular.
Play/Share shortcuts, Play next/Add to queue, local album/artist navigation, Copy file path,
Edit Metadata, ReplayGain apply/remove, Audio Quality Analysis and confirmed deletion reuse
local playback/tag/queue/index services. CUE tracks offer Split into Tracks with confirmation
and a SAF destination picker, private staging and cleanup; virtual-row deletion only removes
the index row. Physical deletion clears shared file index entries and refreshes album rows.
The removed metadata route, Wishlist, format conversion and online actions stay removed.

Every production song ellipsis captures its own root-overlay rectangle before async local
lookup. Song popovers constrain their height to the larger available region above/below the
button and scroll; existing context-menu callers retain their default layout behavior.
Regression checks cover actual row buttons at top/bottom positions in LTR/RTL, access to
the last action, restored menu contents, queue dispatch, clipboard, cancel/confirm physical
deletion, CUE split cancellation and backing-file preservation, editor/analysis navigation,
and album playback controls.
Validation: `flutter analyze` reports **No issues found**; the full `flutter test`
run passes **1,597 tests, 3 skipped**. The focused regression suite passes 42 tests.
The code graph has been refreshed. This follow-up is committed in source; published
Local build 166 predates it and no replacement APK was built during this fix.

**Settings cleanup and Local build 166 (2026-10-19, `3d798c2`):** Detailed logging moves to the
first content group in Logs, retaining its existing persisted switch and log-buffer behavior.
The now-empty App settings category/page is removed; settings search routes logging to Logs.
Embed lyrics, its output-mode submenu, unused preference fields/setters/serialization and
13 retired labels are removed. Local lyrics playback and metadata/lyrics editing remain.
Appearance no longer has the decorative Library preview; color, glass, Player view and
other appearance controls remain. Sistrum Settings/Library subpages reuse the album header's
HeaderCircleButton and back icon; custom selection-mode close controls stay functional.
Build/log numbers increment to 166 for the ARM64 side-by-side Local release.
Validation: generated settings/localizations refreshed; `flutter analyze` reports
**No issues found**, and the full `flutter test` run passes **1,590 tests, 3 skipped**.
The existing log-selection test now scrolls to the first log row after the new switch
increases content height. Removed settings/preview symbols and search entries are absent.
Source changes were pushed before building the verified APK described below.

**Verified ARM64 Local build 166:** Source `b62b3d9e`, version 5.1.1 / build 166,
split versionCode 2166. Built with `SISTRUM_SIDE_BY_SIDE=true`,
`SISTRUM_RUST_ANDROID_ABIS=arm64-v8a` and `flutter build apk --release
--target-platform android-arm64 --split-per-abi --dart-define=GIT_COMMIT=b62b3d9e`.

APK: **54,065,931 bytes**. Audited package `com.amwolfstein.sistrum.local`, label
Sistrum Local, minimum API 24 / target API 37, ARM64 only and all 17 native libraries.
APK CRC/backend checks, AArch64 ELF/ZIP 16 KB alignment, embedded source revision, offline
permissions and cream adaptive icon background pass. APK signatures verify and match
build 165, preserving Local app updates/data. Analysis is clean; 1,590 tests pass, 3 skip.
No physical-device installation/playback test was run in this environment.

Download branch: `apk-local-arm64-166` (APK, README, SHA256SUMS, APK_DETAILS.json).
SHA-256: `5884f74494d15f06897b64461e193c286bfb492edb1a10607f4722aa42b363bd`.

**Local song controls, metadata-page retirement and Genres (2026-10-19, `26f8e71`):** The separate
metadata details route and its display/cover/lyrics/menu/file-action modules are removed,
including the unused barcode visualization/encoder and 69 unused page-only translation
keys. Existing Home, Search, artist, album, Songs and collection song entry points now
start local playback instead of opening the removed route. Player details remain their
separate existing read-only sheet. Per-song menus contain Edit Metadata and Audio Quality
Analysis; the former keeps the existing editor/controller and tag/cover/lyrics persistence,
and the latter opens the retained analysis card/cache/spectrogram workflow. The old
single-file menu actions are removed; existing independent batch operations remain.

A shared song row provides artwork, title plus explicit E badge, artist, circular play
control and ellipsis for Songs, playlists and Loved Songs. Album rows reuse it with track
numbers. Selection/range selection and queue context remain supported. Artist Popular
retains its compact five-per-page layout, with playback on row taps and a song menu.
Edited file tags refresh the library index without changing file/source identity or
unrelated audio facts; changed cover art is extracted to a new library cache entry.
Album rows refresh after saving. Collection rows resolve current scanned tags by ID.

Library categories are Playlists, Artists, Albums, Songs, Genres, Loved Songs and Favorite
Artists. The Loved Songs rename is localized and leaves existing collection keys/backup
formats intact. Genres uses 40-row local SQLite pages over the visible-source view;
blank tags are excluded, semicolon/newline multi-value tags are split, case variants are
grouped, and repeated tags count a song once. Genre selection opens matching local tracks,
with exact tag matching (Rap does not include Trap), the shared row, playback and editing.
Local index changes refresh genre pages. No network catalog or schema migration is added.

Validation: `flutter analyze` reports **No issues found**; the full `flutter test` run
passes **1,590 tests, 3 skipped**. Coverage includes editor availability, menu analysis
navigation, artwork/number rows, album pause/resume, selection and range selection,
Loved Songs/category navigation, tag refresh identity, and real SQLite genre grouping,
exact matching and paging. Songs list controls retain current-track pause/resume.
No APK was built at that source commit; the change is included in build 166 above.
Physical-device validation remains pending.

**ARM64 Local build 165 (2026-10-19):** `c4b79cee` includes the artwork row layout fix
and increments Flutter/log build numbers to 165. Same release flags as build 164:
`SISTRUM_SIDE_BY_SIDE=true SISTRUM_RUST_ANDROID_ABIS=arm64-v8a`,
`flutter build apk --release --target-platform android-arm64 --split-per-abi
--dart-define=GIT_COMMIT=c4b79cee`.

APK: **54,328,531 bytes**, version 5.1.1 / build 165, split versionCode 2165.
Verified **Sistrum Local** / `com.amwolfstein.sistrum.local`, min API 24, target API 37,
only ARM64, all 17 native libraries AArch64 with 16 KB ELF/ZIP alignment, Rust packaging,
offline permissions, cream adaptive background and the embedded source revision. Signature
verification passes and the certificate matches build 164, preserving in-place updates.
Static analysis is clean; **1,609 Flutter tests passed, 3 skipped**. No physical-device
verification in this environment; user confirmation of Loved after updating remains pending.

Download branch: `apk-local-arm64-165` (APK, README, SHA256SUMS, APK_DETAILS.json).
SHA-256: `bcaedfb169b3dec2f3d6e84485608f8c534926a6a0b449913ccf75b9b17a0bf0`.

**Loved local-artwork layout follow-up (2026-10-19):** `c4b79ce` fixes the row layout.
The user confirmed build 164
still displayed one saved Loved track but no row; the device log contained no errors.
The previous no-artwork/ticker test missed the failing local-cover branch. Reproducing
with an actual PNG exposes `BoxConstraints forces an infinite width and infinite height`
at `LocalCoverImage`'s fade Stack inside a collection row. `Image.frameBuilder` wraps the
image outside its own width/height constraints; the expanding Stack therefore received
unbounded list-row axes and prevented the entire track card from laying out.

The shared image fade Stack now passes constraints through to the image, which supplies
its explicit/intrinsic size, while the placeholder fills that resulting size as a positioned
background. Fades and placeholders remain supported. Loved regression coverage includes
real/missing local covers, paused/active tickers, navigation into Loved, finite compact row
bounds and empty-to-populated collection updates. This applies to playlist thumbnails too.
Validation: **42 focused tests pass** for collection playback/selection, real/missing
artwork and image decode/detail behavior. The new real-artwork test failed before the fix
with infinite constraints and no visible row; it passes after the fix, including route
navigation and finite compact row bounds. `flutter analyze`: **No issues found**. Full
Flutter suite: **1,609 passed, 3 skipped**. Build 165 contains this follow-up; the earlier
published build 164 does not. Physical-device confirmation remains pending.

**ARM64 Local build 164 (2026-10-19):** `1d29cf4f` increments the Flutter and log build
numbers to 164, retaining version 5.1.1. Built with the same settings as build 163:
```
source /workspace/toolchains/activate.sh
SISTRUM_SIDE_BY_SIDE=true SISTRUM_RUST_ANDROID_ABIS=arm64-v8a \
  flutter build apk --release --target-platform android-arm64 --split-per-abi \
  --dart-define=GIT_COMMIT=1d29cf4f
```

Output: **Sistrum-Local-arm64-v8a.apk**, **54,328,531 bytes**, version 5.1.1 /
build 164 (split versionCode 2164). Verified app name **Sistrum Local**, package
`com.amwolfstein.sistrum.local`, minimum API 24 and target API 37. The certificate matches build
163, so it installs as an update to Local while retaining the original Sistrum app.
All **17 native libraries** are AArch64 ELF64 with 16 KB-compatible ELF/ZIP alignment.
Rust backend packaging, source revision, offline permissions, signature verification and
the compiled cream adaptive icon background passed inspection. Host and ARM64 Rust backend
were rebuilt by Gradle. Static analysis is clean; the code immediately before the
build-number-only change passed **1,607 Flutter tests, 3 skipped**. Physical-device
installation/playback remains untested in this environment.

APK download branch: `apk-local-arm64-164` (APK, README, SHA256SUMS, APK_DETAILS.json).
SHA-256: `888ab03c7ad9487b7f6895dd8eb7e21e07b4fad6beca0d5bb409f585be165e15`.

**Local Library preference cleanup (2026-10-19):** `5651613` removes Default view and Audio quality
label selection from the Local Library page and settings search. Their picker
sheets, preference fields/serialization, constants, normalization and setters are deleted.
Old settings/backup JSON ignores both retired keys and excludes them when re-exported.
Library sections retain the active/last-used section instead of applying a configured
reset on tab activation; the unused shell-to-Library activation plumbing is removed.

Quality metadata remains available for local playback and file information. Library card
badges and common album-header labels use the former standard measured/stored bitrate
policy, with detected codec fallback for legacy lossy files. Alternate label-mode dispatch,
mode-dependent caches/provider subscriptions and an unused download-completion label helper
are removed. Scanning, folder/source management, duplicate controls and cleanup remain.
Unused control-only translations are removed; shared metadata labels remain.

Validation: generated settings JSON/localizations refreshed; `flutter analyze` reports
**No issues found**. Full Flutter suite: **1,607 passed, 3 skipped**. Coverage checks the
removed rows/search entries, legacy JSON import/export, standard bitrate/legacy codec
labels, preserved tab selection, library scanning/cleanup and local playback. Source search
finds retired preference keys only in the compatibility regression test. Graph refreshed;
no native changes or APK build.

**Earlier Loved row visibility attempt (2026-10-19; incomplete on device):** `964a054` removes the entrance-animation wrapper
from Loved and playlist song rows. A regression test reproduces an invisible single row
while its count remains visible when animation tickers are paused; collection rows now
paint immediately without depending on ticker progress. The same test covers ordinary
animation settings and an empty-to-populated update. Saved collections, playback and
selection behavior remain intact. The physical-device screenshot's exact navigation
sequence has not been reproduced on a device.

Validation: `flutter analyze` reports **No issues found**; **35 focused widget/playback tests
pass**, including the new opacity regression, collection selection/queue behavior and
Sistrum detail headers. No native changes or APK build. Code, refreshed graph and progress
notes use the repository's separate commits.

**Home and Library cleanup (2026-10-19):** Home no longer renders or subscribes to the
Recent access-history section; the separate Search surface retains its existing history.
Latest Releases uses a bounded `release-date-newest` album query over scanned song tags.
Year, year-month, ISO date/timestamp, slash-date and compact YYYYMMDD metadata normalize to
chronological sort keys; invalid calendar dates and undated groups are excluded. An album
uses its newest valid song tag. Equal dates use a stable album key, with no scan/add-time
fallback. The displayed date preserves the source tag's precision rather than presenting
an invented January 1 for year-only metadata. Home's Recently Added loader/order is unchanged.

Library overview now contains only matching category rows: Playlists, Artists, Albums,
Songs, Loved and Favorite Artists. The last two open their existing local collection pages.
The overview no longer queries, renders or pages the Recently Added album grid. Albums,
Artists and cross-library search retain their existing bounded queries. Dedicated Songs
removes collection/individual-playlist rows and includes playlist-member songs instead of
hiding them; Playlists remains in its own section.

Validation: `flutter analyze` reports **No issues found**. **26 focused tests pass**, covering
release metadata versus scan time, date formats/calendar validation, stable cursor pages,
metadata updates, original tag display, unchanged Recently Added ordering, no Home history
subscription, Library row ordering/routes, no overview album query and songs already saved
in playlists. Final full Flutter suite: **1,613 passed, 3 skipped**. No native code/schema changes
or APK build. Graph refreshed from the finished source. Per the user's request, this phase
uses one combined commit, then publishes to `main`, including the previously committed guide
consolidation (`f5d0afd` through `eb7aa5d`).

**Unified first-run guide (2026-10-19):** `f5d0afd` removes the obsolete download/output-folder
setup page, folder selection/recovery handlers and output-directory writes from setup.
The existing local search, playback, Library, music-folder and settings tips now live in
`local_guide_pages.dart` inside the same setup PageView, after Welcome/language and before
permissions. This yields nine steps on Android 13+ and eight on older Android versions,
sharing one counter and Back/Next navigation. Get Started sits on the former penultimate
permission step (notifications on Android 13+, storage otherwise) and opens Home directly.
The separate TutorialScreen is deleted; its old route redirects to unified setup. Both
completion flags are persisted together before publication, preventing a second guide after
completion/restart. Versioned progress drafts retain their page and notification skip choice;
legacy permission/folder indices migrate to their corresponding retained permission page,
ignoring former output-folder fields. Local Library settings still select scanning folders.

Unused setup-folder and duplicate welcome translations were removed. The guide copy checks
also exposed incorrect Hindi/Russian app-name translations, now corrected. Regression tests
cover both Android permission layouts, integrated tip titles, Back navigation/resume, old
folder drafts, permission refresh, optional notification skipping, Home completion, atomic
completion flags and restart routing. The obsolete iOS output-folder setup test was deleted.
`flutter analyze` reports **No issues found**; the final full suite passes **1,610 tests,
3 skipped**. The initial full run identified that obsolete iOS test as its only failure;
the final run is clean. Graph refreshed (`e15e51a`) and no TutorialScreen node remains.
No native code changed, APK was built, or commits were pushed for this task.

**Wishlist removal (2026-10-18):** `d44a273` removes Wishlist Library cards/rows and
navigation, track-menu actions, folder mode, provider mutation APIs, state/index fields,
backup counts/preview rows/restore commands, hydration/export paths and localized strings.
Native collection reads and restore publication now use schema v3 with only retained
collections. The upgrade drops the obsolete table from v1/v2 databases without rewriting
Loved, playlists or favorite artists. Older JSON/preferences imports ignore removed data;
new collection exports omit it. Playlist hydration now has its own named accumulator.

Validation: `flutter analyze` reports **No issues found**; the full Flutter suite passes
**1,611 tests, 3 skipped**. New regression tests cover real SQLite v1/v2 upgrades preserving
retained rows, ignored malformed legacy JSON and absent Wishlist menu actions. Existing
collection mutation/rollback, paging, hydration, backup and playlist playback coverage was
adapted to retained collections. `bash scripts/check_rust_backend.sh` passes formatting,
Clippy with warnings denied and **227 Rust tests, 1 ignored**. Device integration fixtures
were updated to schema v3 but not executed without a device. Source search leaves only the
obsolete-table deletion and regression fixtures; the refreshed graph query finds no
Wishlist nodes (`e6015e5`). No APK was built in that removal task. Its commits were subsequently pushed to `main`
through `39ba329` at the user’s request.

**ARM64 Local build 163 and contrasting icon (2026-10-18):** `1474c860` replaces the black
launcher background with light cream (`#FFF4DF` for the adaptive icon), keeps the existing
green adaptive/monochrome logo, and regenerates the Android launcher resources. The legacy
raster icon uses the matching cream-background design. Increments `pubspec.yaml` and the
in-app log build number from 162 to 163 while retaining version 5.1.1. The existing
side-by-side switch keeps **Sistrum Local** / `com.amwolfstein.sistrum.local`, separate from the
original Sistrum package.

Built using the same release/side-by-side settings as build 162, with ARM64 only:
```
source /workspace/toolchains/activate.sh
SISTRUM_SIDE_BY_SIDE=true SISTRUM_RUST_ANDROID_ABIS=arm64-v8a \
  flutter build apk --release --target-platform android-arm64 --split-per-abi \
  --dart-define=GIT_COMMIT=1474c860
```

Output: **Sistrum-Local-arm64-v8a.apk**, **54,345,707 bytes**, version 5.1.1 / build 163
(split manifest versionCode 2163), minimum API 24, target API 37. The signed manifest confirms
`com.amwolfstein.sistrum.local`, label Sistrum Local and only `arm64-v8a`. All **17 native
libraries** are AArch64 ELF64 with 16 KB-compatible ELF/ZIP alignment. Rust packaging, source
revision, offline permissions, light legacy icon backgrounds and the compiled cream adaptive
background passed inspection. `apksigner verify` passes; the certificate matches the previous
Local APK, enabling an update without uninstalling or changing the original Sistrum app.

Static analysis is clean. The application code passed **1,615 Flutter tests, 3 skipped**
immediately before this icon/version-only change. The host and ARM64 Rust backend were rebuilt
in the APK build. Graph refreshed after the source commit. Physical-device testing remains
pending. Latest collection-action commits were pushed to `main` through `bbc56e0`; icon/build
source and this record are pushed with this build.

APK download branch: `apk-local-arm64-163` (APK, README, SHA256SUMS and APK_DETAILS.json).
SHA-256: `bef4e5213fcb40cb529b809c4605a840a50cfcb05dd780a20cef39845410b83f`.

**Centered collection playback actions (2026-10-18):** `d78043f` updates the shared album/playlist action
row now includes both Play/Pause and Shuffle between Loved on the left and Add to playlist
on the right. Previously the presence of the two outer icons hid the inline Shuffle action,
leaving it in the corner toolbar. Removes the toolbar Shuffle controls from local albums and
Library collection folders; playlists, Loved and Wishlist all use the corrected shared row.

Reuses the existing filled Play and translucent Shuffle pills, with equal available widths,
compact padding/icons/type and 48px minimum touch heights. Outer Loved/playlist icons use
48px targets. The physical left-to-right order remains consistent with RTL metadata. Header
colors, playback/pause behavior, shuffle queue loading, Loved mutations, playlist picking,
playlist editing/export, selection and the separate artist header are preserved.

Validation: `flutter analyze` reports **No issues found**; full `flutter test` reports
**1,615 passed, 3 skipped**. Focused tests cover the four controls'
order, bounds, touch targets, styling and callbacks in light/dark, 320px widths, RTL and 2x
text. Album and playlist playback checks exercise Shuffle from the new row; playlist/Loved/
Wishlist screen tests check that no toolbar Shuffle remains. The graph was refreshed after
the code commit. No APK was built in that change; the commits were subsequently pushed to
`main` through `bbc56e0` and are included in the new build 163 recorded above.

**Selectable player view and History View cleanup (2026-10-18):** `c609d90` adds
**Player view → Normal view / Immersive view**. Normal remains the default. The preference
uses the existing Sistrum full-bleed artwork layout/background rather than adding another
player implementation. Immersive portrait artwork stays edge-to-edge while paused and fades
into the existing controls; landscape keeps the established two-column layout. The saved
theme setting loads at bootstrap, survives subsequent theme edits and serializes safely;
unknown/missing values fall back to Normal.

The full cover stays mounted while lyrics/queue panels fade, with pointer/semantics and hero
ownership handed to the compact header. View changes and rotation replace the background
without retaining duplicate global artwork keys. Both views use the existing seek, playback,
volume, lyrics, queue and track-navigation controls and mini-player dismissal geometry.

Removes the Layout/History View selector, Settings search result, app-setting field, setter,
JSON serialization and obsolete localized strings. Older imported JSON containing the retired
field is accepted and ignores it. Library overview cards and dedicated section rows retain
their structural layouts without reading the removed preference.

Validation: `flutter analyze` reports **No issues found**; full `flutter test` reports
**1,609 passed, 3 skipped**. Focused tests cover persistence in light/dark,
legacy settings, search navigation, full-bleed geometry, pause, small portrait and landscape,
rapid lyrics/queue transitions, track changes, live view switching and both mini-player
dismissal paths. Production-source/ARB searches confirm no retired History View preference,
selector or localization references remain. Graph refreshed after the code commit. No APK
built. The player-view commits were subsequently pushed to `main` through `f63648a`.

**Format conversion removal (2026-10-18):** `19a28b3` removes Convert Format from the file metadata
menu and Convert actions from Library/queue, search results and album track selection.
Deletes the conversion sheet, lossless encoding/quality/resampler options, batch conversion
runner, conversion-specific SAF publication/history persistence, library replacement methods,
automatic conversion helpers and codec probes/cache used only by conversion. All conversion
localization keys are removed across the ARBs; bitrate and original-cover labels now have
neutral keys. Setup, tutorial and cache text no longer advertise conversion.

CUE splitting is extracted into `ffmpeg_cue.dart`; retained metadata, CUE and ReplayGain UI
helpers move to `track_metadata_file_actions.dart`. File tag/cover/lyrics editing, ReplayGain,
artwork dimension probing, safe temporary-output publication and built-in playback remain.
Conversion-specific tests are retired; shared selection and metadata menu tests assert the
absence of conversion while retaining playback, ReplayGain and metadata editing coverage.

Validation: `flutter analyze` reports **No issues found**; full `flutter test` reports
**1,598 passed, 3 skipped**. Search/selection regressions pass in both theme variants and
portrait/landscape layouts. Source and ARB searches confirm the removed conversion entry
points, services and localization keys are absent. Graph refreshed after the code commit.
No APK built. The conversion-removal commits were subsequently pushed to `main` through
`ffab9ba`.

**Settings cleanup (2026-10-18):** `8fa30b9` removes the obsolete Files & Folders
output-folder page and download-era Metadata page, their root Settings destinations and
nested search entries. Their unused setters and picker-specific widget tests are removed;
local file metadata editing and compatibility fields used by tag rewriting remain. Music
source folder management stays in Local Library. Existing setup/folder-grant handling remains.

Playback uses the built-in player exclusively. The Player chooser, Now Playing external-player
actions, player-mode model/serialized field and setter, mode-based automation gates and all
external playback/fallback branches are removed. Old JSON/backups containing `playerMode`
are accepted but ignore that unknown key. Each playback entry point requires successful
built-in initialization; failure reports an error without opening another app. Queue selection,
Previous/Next, CUE checks, ReplayGain, AutoMix, autoplay, mute/headphone automation and USB
hardware/output controls are preserved. The automation helper's enable flag now controls only
automation, rather than switching a player implementation.

Validation: `flutter analyze` reports **No issues found**; full `flutter test` reports
**1,625 passed, 3 skipped**. Focused regression checks cover Settings/search absence, legacy
JSON compatibility, all four playback entry points refusing external fallback on initialization
failure, queue ordering and enabled built-in controls. Retired tests covered the removed picker
pages and external-mode behavior; setup's folder-grant test and local tag-mode compatibility
coverage remain. Production source was searched to confirm no remaining removed page classes,
player-mode consumers or external-player actions. Graph refreshed after the code commit.
No APK built or GitHub push performed for this cleanup; the installed APK predates it.

**Artist Popular refinement (2026-10-18):** `7056525` replaces Songs and numeric arrow
pagination with **Popular**, five songs per page and tappable dot indicators. It shows at
most 20 unique available local tracks (four dots when 20 tracks are available; fewer for a
smaller artist library). Recorded all-time play counts determine rank, with random selection
and tie order for unplayed tracks/no history. The selection stays stable while the page is
open. Reads scan the artist in bounded 40-track pages, retain only the best 20 candidates and
query aggregated listening counts for each page's local path/ID identities. Listening database
version 2 adds a track-key index while preserving existing history. Pending recorder writes
are flushed before statistics reads.

All artist Show-more controls are removed. Albums/Singles continue loading bounded pages
when swiped near the shelf end, with Retry only for failed reads. Artist Play still loads the
entire artist queue; its loader is retained during startup so the Popular cap cannot truncate
or dispose playback. The newest featured release and tag-based Singles/Albums rules remain.

Validation: `flutter analyze` reports **No issues found**; full `flutter test` reports
**1,630 passed, 3 skipped**. New provider/SQLite tests cover most-played ranking across page
boundaries, summed play counts across days, random fallback across the entire artist library,
unique 20-track caps and smaller libraries. Light/dark widget tests verify four interactive
dots, no numeric counter or Show-more controls, automatic discography pagination past 40
releases and full 41-track playback. Rendered light/dark previews were inspected. Graph
refreshed after the code commit. No APK built or GitHub push performed for this refinement;
the installed APK predates this change and the fragmented Opus header follow-up.

**Fragmented Opus header follow-up (2026-10-18):** Device scan found 1,949 tracks with
28 metadata errors, all "Ogg header spans too many pages". The previous 1,024-page cap still
rejected comment/artwork packets below the 64 MiB byte budget when spread across small pages.
`3afd609` removes that cap for metadata, artwork and tag editing. The existing 64 MiB header
byte limit remains; audio-quality identification probing retains its short 10-page limit.
Readers still stop after the two required header packets and do not scan audio for tags/art.
Malformed/truncated comments retain explicit diagnostics. No claim is made that the 28 actual
files were examined: regression fixtures exercise the pagination failure shown in the log.

Validation: the expanded Opus regression suite fails against the pre-fix readers/writer
(5 failures with the page-limit error), then passes **8/8** with the fix. Coverage includes
512 KiB comments and artwork across thousands of pages, local scan metadata, tag edits
preserving audio bytes, invalid/truncated comments and a continued packet exceeding the
64 MiB byte limit. `bash scripts/check_rust_backend.sh` passes formatting, Clippy and the
full Rust workspace suite: **227 passed, 1 existing ignored**. No Dart/Flutter behavior or
bridge signatures changed. Graph updated after the code commit. No Android/native release
or APK build was run; the previously delivered APK does not contain this fix.

**Side-by-side ARM64 APK (2026-10-18):** `eb33f36` adds opt-in
`SISTRUM_SIDE_BY_SIDE=true` Gradle configuration. It sets the app name to **Sistrum Local**
and application ID to `com.amwolfstein.sistrum.local`; ordinary builds retain the original identity.
The packaged manifest also has unique provider authorities, with the original activity class
resolved correctly under the new application ID. App settings/data and folder permissions are
independent of the original installation. Graph refreshed in `3942d11`.

Built with:
```
source /workspace/toolchains/activate.sh
SISTRUM_SIDE_BY_SIDE=true SISTRUM_RUST_ANDROID_ABIS=arm64-v8a \
  flutter build apk --release --target-platform android-arm64 --split-per-abi
```

Output: **Sistrum-Local-arm64-v8a.apk**, 54,510,467 bytes, version 5.1.1 / Flutter build 162
(ABI split manifest versionCode 2162), minimum Android API 24. `aapt dump badging` verifies
name/package and only `arm64-v8a`; all 17 native libraries were checked as AArch64 ELF64,
including the rebuilt Rust backend. `apksigner verify` passes (v2 signature). No physical device
was attached, so installation/playback testing remains pending. The previously validated
Flutter source passed 1,626 tests (3 skipped); this change only affects Android build identity.
APK download branch: `apk-local-arm64-162` (artifact only).
SHA-256: `ddb29a6b7ae632ab614b4c9d48be0df7c99ab7ac85d4d0bf8b083f822d6e9823`.

**Home feed correction (V2, 2026-10-18):** `45e5f17` restores the original Apple Music
large featured-card composition, horizontal album/playlist shelves and circular artist cards.
Featured entries are ordered by local release-date tags; Recently Added uses SQLite ordering
and a 12-track limit instead of hydrating/sorting the full library. Album cards load the exact
local album key, playlist cards open saved collections and artist cards open the V3 detail page.
Scan/index changes refresh the feed; read failures offer Retry. Existing search and recent
access remain available. All artwork stays local. Saved playlist summaries are sorted by
last edit and limited to 12 cards. No online service or home-provider setting is restored.

Validation: `flutter analyze` reports **No issues found**; full `flutter test` reports
**1,626 passed, 3 skipped**. New tests cover scan refresh, disabled-library reads, bounded
shelves, light/dark layouts at 360px with 1.6x text, and local artist navigation. Rendered
layout previews were inspected. Graph refreshed after the code commit (`7c9a08b`). No APK
or GitHub push performed for this change.

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
  `track_provider` + Sistrum home search, and motion artwork.
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
online-coupled (`extension_provider` registry, `track_provider`, Sistrum home search) is consumed
only by the download engine and is removed with it in Phase 6. Two now-dead settings
(`homeFeedProvider`, explore-feed cache row) are deferred to the Phase 8 settings purge (V4).

**Phase 6 summary (historical; Phase 7 changes below supersede the native/history details):** the app is now a local-only player in Dart. The download engine, extension
registry, `track_provider`, Sistrum home search and all download/verification UI are gone; the
player, queue and search read the local library DB. Per PD2 the Dart SQL layer no longer queries the
download history, but `history.db` remains ATTACHed and the native library scan still excludes it —
both re-homed to Rust in Phase 7. Two kept-but-dormant pieces (`downloaded_embedded_cover_resolver`,
the `history.db` attach) are slated for Phases 7-8. `flutter analyze` repo-wide is clean; full
`flutter test` passes (only the known-flaky perf test).

**Phase 7 implementation:**
- `a9f63b9` pruned core online-support modules; `fa2afff` completed the reduction.
- `7d54453` refreshed the graph from code commit `fa2afff0`.
- New `sistrum-local` crate owns local scans, CUE handling, metadata/tag writes, artwork,
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
- Sistrum is the sole production theme, with existing light/dark, accents, glass and font
  controls. Old Material preferences restore as Sistrum. The old Material theme is retained
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
  `/workspace/Sistrum-offline.apk` for download.
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

**Post-Phase 8 Opus scan fix (2026-10-18, `6500a82`):**
- Device build 161 reported widespread SAF Opus tag failures. Reproduced a reader defect
  with a real FFmpeg/libopus silence fixture: valid encoder-only comments were rejected
  unless a title, artist or ReplayGain field existed. Accept structurally valid comments,
  including album/lyrics-only metadata; retain filename display defaults and quality probing.
- Preserve parser diagnostics as `metadataReadError` and forward them through SAF failures;
  malformed comments still fail. No file conversion or library reset is required.
- Build **5.1.1+162**. Regression coverage includes Arabic display names, album/lyrics-only
  tags, malformed comments, and repeated borrowed-descriptor reads with/without artwork.
- Rust fmt/clippy clean; **219 tests passed, 1 existing ignored**. Both Android native ABIs
  built. Kotlin app/instrumentation compilation and **63 JVM tests** passed; Flutter
  analysis clean and **6 metadata bridge tests** passed.
- Graphify refreshed: **22962 nodes, 44586 edges**, source provenance `6500a82`.
- Release APK built for ARM64/ARMv7 with source commit `6500a82`. Both split packages
  passed backend/CRC audits, APK signature verification (same certificate as build 161),
  16 KB ZIP alignment and offline/non-debuggable manifest checks. All **17 ARM64 native
  libraries** have at least 16 KB ELF LOAD alignment; fixed native-reader marker verified.
- Download branch: `apk-opus-fix-162` (artifact-only, separate from `main`), with independently
  installable ARM64/ARMv7 APKs, installation instructions and SHA256SUMS.
  ARM64 SHA-256: `2f462b2737af65adacb3c8c1859bfec1516b7ce0cace4f179ff3b34e2adadba6`.
  ARMv7 SHA-256: `d2ed3168621ff4e1cd5e0bbae0453f2587c247730dd76c818725924ee6d4780b`.
- The user's actual audio files and physical Android device are unavailable here; this
  fixes a confirmed failure case consistent with the log, not a verified diagnosis of
  every reported file. Device rescan remains to be checked after installing build 162.

**Follow-up Opus continuation fix (2026-10-18, `34133cc`):**
- The follow-up device log now reports `no Vorbis comments found`. Reproduced this exact
  error with a valid comment packet spanning more than 80 pages. The reader also silently
  discarded packets larger than 10 MiB, including large artwork/padding headers.
- Metadata/artwork now assemble the first two header packets within the writer's bounded
  1024-page / 64 MiB limits. They stop before scanning audio packets. Truncated, interrupted
  or over-budget headers produce specific failures instead of a misleading missing-tag error.
- Quality reads only the identification packet, so large comments do not suppress rate,
  duration and bitrate probing. Regression coverage includes >80-page comments, >10 MiB
  packets, continued artwork, bounded reads, truncated headers, and a real FFmpeg Opus
  stream rewritten with a 6 MiB tag and scanned through a borrowed descriptor.
- Fixed the hardcoded exported-log/about build number from 161 to 162 to match pubspec.
  The follow-up log's build 161 label alone does not identify the installed APK.
- Rust fmt/clippy clean; **223 tests passed, 1 existing ignored**. Flutter analysis:
  **No issues found**. No APK or Android release/native-library build was run for this fix.
- Actual user audio files are unavailable here; the precise on-device header layout remains
  unverified. This corrects reproduced parser failures that yield the reported error.
- Changes are committed locally; no GitHub push or artifact publication was performed.

**V3 detail-design correction (`0e6c88e`, 2026-10-18):**
- Recovered the former Sistrum artist/album/playlist designs from Git history rather than
  retaining the generic local artist destination. `LocalArtistScreen` restores the portrait
  identity header, centered Play between Favorite and Shuffle, featured release card,
  five-song carousel, and separate Albums/Singles discography shelves.
- Artist links from metadata/now-playing, album subtitles, home/search, library and favorite
  artists now open the local detail page. Existing favorite entries are matched by local
  artist name; no provider lookup is needed. Local artist reads are paged, support retry
  and disposal, refresh after scans, and build a complete playback queue beyond the first page.
- Album/playlist headers reuse the original immersive artwork, Love / primary playback pill /
  Add-to-playlist composition and release/count/duration footer. Keep shuffle in the toolbar,
  album play/pause/resume, selection, metadata navigation, playlist rename/cover/export actions.
- The featured card follows release-date tags, with scan recency as a tie-breaker. Classification
  uses total-track/disc tags, not the number of files currently stored: explicit one-track,
  single-disc releases are Singles; larger totals, EPs, partial albums and unknown totals are
  Albums. SQLite regression coverage includes an old album added today and one stored track
  from a 12-track album. No EP classification is inferred from the local file count.
- FLAC/Opus readers now honor separate `TOTALTRACKS`/`TRACKTOTAL` and `TOTALDISCS`/`DISCTOTAL`
  comments independently of tag order, retaining valid number-pair totals when separate values
  are invalid. Previously scanned files require a full rescan to populate newly recognized tags.
- Validation: Flutter analysis **No issues found**; full `flutter test` **1623 passed, 3 skipped**;
  focused detail/paging/release/playback/metadata tests **12 passed**. Rust fmt/clippy clean;
  workspace tests **225 passed, 1 existing ignored**. Render checks used the same widget fixtures
  in light/dark and narrow screens with larger text. No Android APK/native release build or
  physical-device run was performed. Corrected the contradictory Phase 6 PD1 decision.

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
- `core/src` has **zero** `use sistrum_{network,extensions,providers}` hits → pruning core is
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
  `proguard-rules.pro` keeps `com.sistrum.backend.**`, Kotlin `SelectedCoreBackend.kt` /
  `NativeDataJobs.kt` import the generated bindings.

**Biggest product coupling**
- `download_history_provider` is imported by `music_player_provider` (`:5`, `:24-27`, `:148-262`)
  and `playback_provider` (`:3`, `:114-116`, `:362`) plus >28 other files. The player's
  "library identity / playable queue" currently derives from `DownloadHistoryItem`.
  → Removing downloads requires re-pointing the player to the local library DB.

**Platforms / assets**
- Platforms present: `android/`, `ios/` only (no macos/windows/linux/web).
- `third_party/`: keep `audio_service`, `audioplayers_android`; remove `discord/` (35 MB `.gpg`)
  and `sistrum_discord/` (**pubspec path dep** → must edit `pubspec.yaml` + regenerate lock).
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

- **V1 — Sistrum theme only.** Remove all other themes and the theme picker; Sistrum is the sole
  look. Phase 8 retains light/dark, Sistrum accents, glass and local font controls; the
  alternate Material theme and picker are removed.
- **V2 — Home feed → local.** Rewire the home feed provider off Apple Music to local content.
  Implemented (2026-10-18): original large editorial cards for latest locally available
  releases (release-date tags), followed by Recently Added songs, local Albums, saved Playlists
  and circular Artists shelves. Recent access/history remains beneath the feed. Each database
  shelf reads at most 12 entries and refreshes with the library index; playlist cards use saved
  collection summaries. All artwork and destinations are local. Search stays a separate mode.
- **V3 — Reuse Sistrum "online" theming for local artist / album / playlist screens**, replacing
  the old local styling. Implemented by restoring the original detail composition over local
  data; artist navigation no longer opens a generic filtered album browser. Preserve local
  playback, selection, metadata, collection editing and export actions.
  User refinement (2026-10-18): center artist Play between Favorite and Shuffle; highlight
  the newest locally available album/single by release-date tags (scan recency breaks ties).
  Classify Singles only from an explicit total-track count of 1, excluding multi-disc releases.
  Larger totals, including EPs and partially stored albums, belong under Albums. Unknown totals
  stay under Albums rather than treating one stored song as proof of a single.
  User refinement (2026-10-18): Popular replaces Songs, capped at 20 tracks with five per
  page and at most four dots. Rank by all-time local play counts; unplayed tracks fill any
  remaining places randomly, with a stable order for the open page. Remove artist Show-more
  controls; album/single shelves fetch the next bounded page automatically near the end.
  The artist Play button continues to load the complete local artist queue.
- **V4 — Remove all online-service settings** (extensions/store, providers, downloads, network
  storage, Discord, updates/remote-config, profile, donate, plus online rows inside
  Music/Library settings).

Impact on phases: Phase 5 keeps a **localized** home feed (not dropped); adds a **theming
consolidation** workstream (Sistrum-only + style port); Phase 8 settings purge = all online settings.

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
Remove: `third_party/sistrum_discord/`; `lib/services/discord_presence_service.dart`,
`discord_artwork_resolver.dart`; `lib/widgets/discord_presence_settings.dart`; Discord refs in
`main_shell.dart`, `music_player_runtime.dart`, `settings/playback_settings_page.dart`;
`models/settings.dart` `discordRichPresenceEnabled`; l10n `discordPresence*` keys (all 20 arb);
`flutter_secure_storage` only if no other user (verify `secure_storage_options.dart`);
`integration_test/discord_sdk_test.dart`, `test/discord_*_test.dart`.
Edit: `pubspec.yaml` (drop `sistrum_discord`), `pubspec.lock` (regen), `android/app/build.gradle.kts`
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
`library_tracks_folder_screen`, `sistrum_library_screen`, `track_metadata_edit_sheet`,
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
   Verify: `cargo test -p sistrum-core`.
2. **Re-home local `extensions::backend` pieces** (library scan + tags) into `core` or a new
   `local` module, decoupled from `ExtensionEnvironment`/`NetworkService`.
3. **Reduce `mobile` to local-only**: drop `manager.rs`, `extensions.rs`, `repository.rs`,
   online `metadata.rs`/`lyrics.rs` methods, `network_tags.rs`, `tags.rs:243` cover download;
   re-point local `impl` methods onto the re-homed local type. Keep `bindgen` + regen bindings.
4. **Delete `providers`, then `network`, then `extensions`** once unreferenced.
5. **Update build config**: `rust_backend/Cargo.toml` (members, workspace deps, patch), `Cargo.lock`,
   `scripts/build_rust_backend.sh` (drop ios), `scripts/check_rust_backend.sh`,
   `scripts/check_android_statx.sh`, `android/app/build.gradle.kts` (sourceSets/build task),
   Kotlin `SelectedCoreBackend.kt` / `NativeDataJobs.kt` / `CoreBackend.kt`, `SistrumBackend.podspec`,
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
