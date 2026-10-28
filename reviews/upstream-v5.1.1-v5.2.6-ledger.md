# Upstream ledger 5.1.1 → 5.2.6 (`5a895265..c90ec647`)

Every upstream commit in the range, checked one by one on 2026-10-27/28 at the owner's request
("all upstream from the first commit to the latest, in all aspects"). Verdicts:

- **RECORDED**: ported earlier; the ID is in `reviews/UPSTREAM.md`.
- **DONE**: ported in this pass (U-509..U-516).
- **N/A**: does not apply to the offline Android Sistrum player (reason given).
- **TRANSLATION**: locale strings; handled by the translation import batch.

Counts: DONE 12, N/A 339, RECORDED 144, TRANSLATION 38

| Commit | Date | Subject | Verdict |
|---|---|---|---|
| `e76ccc3f` | 2026-09-29 | fix(extensions): return verification-required when challenge minting fails | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `ac8523d7` | 2026-10-12 | feat(metadata): add per-field download tag separators | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `65dbce27` | 2026-10-12 | fix(automix): wait for advancing audio before starting fades | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `e3b69a25` | 2026-10-13 | fix(download): probe M4A streams before preserving requested FLAC | N/A: downloads removed |
| `e56d59c7` | 2026-10-13 | feat(theme): adopt Material Symbols and expressive components | N/A: Material / Material Expressive only (Sistrum is the sole theme) |
| `0b3b9c21` | 2026-10-13 | feat(theme): show a check on selected expressive switches | N/A: Material / Material Expressive only (Sistrum is the sole theme) |
| `186c66ae` | 2026-10-13 | fix(lyrics): refresh LRC sidecars in their actual SAF folder | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `c0fd506c` | 2026-10-13 | fix(storage): preserve audio MIME when publishing SAF downloads | N/A: downloads removed |
| `62ce4043` | 2026-10-13 | feat(ui): extend Material Expressive surfaces and playback controls | N/A: Material / Material Expressive only (Sistrum is the sole theme) |
| `e049604b` | 2026-10-13 | feat(lyrics): add SpotiFLAC fallback for Apple Music outages | N/A: online lyrics removed |
| `5e6afc7a` | 2026-10-13 | feat(ui): add Material Expressive spring motion | N/A: Material / Material Expressive only (Sistrum is the sole theme) |
| `8f6aa001` | 2026-10-13 | feat(settings): connect standard Material settings rows | N/A: Material / Material Expressive only (Sistrum is the sole theme) |
| `ef600973` | 2026-10-13 | style(material): align tonal surfaces and control shapes | N/A: Material / Material Expressive only (Sistrum is the sole theme) |
| `736cfcd0` | 2026-10-14 | feat(settings): connect custom Material settings rows | N/A: Material / Material Expressive only (Sistrum is the sole theme) |
| `56e2eb85` | 2026-10-14 | feat(material): animate header action groups and collapse | N/A: Material / Material Expressive only (Sistrum is the sole theme) |
| `9bac4a6e` | 2026-10-14 | feat(material): unify progress and surface transitions | N/A: Material / Material Expressive only (Sistrum is the sole theme) |
| `83a55fb8` | 2026-10-14 | feat(library): add sectioned browsing and adaptive fast scrolling | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `8d1a42e0` | 2026-10-14 | feat(player): refine mini-player and queue feedback | N/A: Material Expressive mini player and queue feedback |
| `97d8ee36` | 2026-10-14 | fix(player): prevent overlapping titles during rapid skips | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `08266c73` | 2026-10-14 | feat(listening): add Rewind highlights and refresh statistics | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `3fd15881` | 2026-10-15 | fix(library): align filter and sort sheet sizing and dismissal | DONE `f609257` (U-515): Library filter sheet fits content, title carries Reset; separate sort sheet N/A (sort lives in the filter sheet here) |
| `d96a9b56` | 2026-10-15 | fix(extensions): use adaptive icons for installed extension avatars | N/A: extensions removed |
| `ba737c62` | 2026-10-15 | feat(listening): show a skeleton while statistics load | DONE `f609257` (U-514): Listening statistics skeleton while loading |
| `3dc2d690` | 2026-10-15 | fix(audio): preserve FLAC precision in Android bit-perfect playback | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `c42b3140` | 2026-10-15 | fix(player): expose favorites and shuffle in Material notifications | N/A: Material notification path; Sistrum notification already has favourite and shuffle |
| `1cc233bd` | 2026-10-15 | fix(settings): unify adaptive sheet layout and drag behavior | DONE `f609257` (U-515): AppScrollableSheet / showAppScrollableBottomSheet; auto-scan and language pickers moved; download/files/metadata/extension pickers N/A |
| `9495a6bf` | 2026-10-15 | fix(metadata): align separator picker with Settings components | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `bd0b4a50` | 2026-10-15 | feat(layout): adapt tablet navigation and center wide content | DONE `f609257` (U-516): 840dp reading width without the 32dp cap, page titles align to centred content, shorter landscape header, Library overview and Listening statistics centred; tablet rail already here; Material rail, online and extension screens N/A |
| `1bae2e6b` | 2026-10-15 | refactor(ui): unify expressive actions and modal transitions | N/A: Material / Material Expressive only (Sistrum is the sole theme) |
| `d28e3f65` | 2026-10-15 | fix(headers): fit artwork and unify toolbar controls | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `8ff1490d` | 2026-10-15 | fix(settings): use shared sheet for log level selection | DONE `f609257` (U-512): log level picked from the shared sheet |
| `33dca89f` | 2026-10-15 | feat(ui): unify content cards and preserve press behavior | N/A: Sistrum call sites pass sistrumSurface: false and keep the plain Card we already use |
| `c5491302` | 2026-10-15 | feat(ui): add themed menus and adaptive checkbox rows | N/A: Material Expressive menus and checkboxes; Sistrum keeps its own menus |
| `bf8ae854` | 2026-10-15 | feat(forms): adopt expressive inputs with consistent form state | N/A: Material / Material Expressive only (Sistrum is the sole theme) |
| `318fbe71` | 2026-10-15 | refactor(ui): use shared loading indicators | N/A: structural refactor (port rule: port behaviour, not refactors) |
| `1d53bf93` | 2026-10-15 | feat(rewind): add yearly highlights and seasonal library banners | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `2111afa4` | 2026-10-15 | feat(player): share volume controls across Material and Sistrum | N/A: rename SistrumVolumeControl to PlayerVolumeControl; Sistrum behaviour unchanged |
| `23fe78f3` | 2026-10-15 | feat(loading): align skeletons with collection and extension layouts | N/A: changes Material, extension-store and online-search skeletons; the Sistrum collection header skeleton is unchanged |
| `47ccf9c9` | 2026-10-15 | fix(player): size volume slider handle proportionally | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `56a526ca` | 2026-10-15 | chore(release): bump app to 5.2.0 build 162 | N/A: release bookkeeping |
| `2bf50ecb` | 2026-10-17 | fix(verification): bound browser handoffs and release expired dialogs | N/A: credential storage / verification removed |
| `09e07671` | 2026-10-17 | fix(downloads): recover native queues when their service dies | N/A: downloads removed |
| `1e73ffea` | 2026-10-17 | feat(i18n): add player feature text and clarify built-in playback | TRANSLATION: pending translation import batch |
| `befcd2ad` | 2026-10-17 | feat(a11y): label controls and improve settings contrast and targets | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `21fd51d6` | 2026-10-17 | feat(autoplay): enable personalization by default and confirm learning resets | DONE `b3f4244` (U-509): Learn from listening on by default; Reset learning asks first |
| `ecf594aa` | 2026-10-17 | feat(equalizer): add multiband EQ and per-player native audio processing | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `40f65d3a` | 2026-10-17 | feat(player): show audio source processing and output details | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `78a5e078` | 2026-10-17 | feat(lyrics): share lyric cards and refine timed vocal transitions | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `11c6cf99` | 2026-10-17 | feat(player): synchronize music haptics with local playback | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `161a216b` | 2026-10-17 | fix(automix): align effect handoffs and render sufficient source audio | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `6debfccb` | 2026-10-17 | fix(theme): retain dominant cover colors in player backgrounds | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `3d11169f` | 2026-10-17 | fix(network): request Android 17 local network access before NAS connections | N/A: network storage removed |
| `eae2ec9d` | 2026-10-17 | chore: ignore local release assets | N/A: release-asset ignore rules for desktop packaging |
| `05a56133` | 2026-10-17 | feat(player): add configurable full-screen cover art | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `d2d5593b` | 2026-10-18 | ci: include integration tests in Dart change detection | N/A: release/CI/docs |
| `a396bcf0` | 2026-10-18 | refactor(metadata): reuse the platform tag mapper | N/A: structural refactor (port rule: port behaviour, not refactors) |
| `4b732439` | 2026-10-18 | chore(l10n): remove unused settings group messages | TRANSLATION: l10n housekeeping (pending translation import batch) |
| `fdcd291c` | 2026-10-18 | refactor(android): remove unreachable backend dispatch fallbacks | N/A: structural refactor (port rule: port behaviour, not refactors) |
| `0a9013c9` | 2026-10-18 | refactor(ios): simplify supported OAuth session handling | N/A: desktop/iOS only |
| `181900a2` | 2026-10-18 | test(library): share re-enrichment settings fixtures | N/A: upstream test/CI/docs housekeeping (our tests are separate) |
| `317cd254` | 2026-10-18 | test: declare the path provider interface dependency | N/A: upstream test/CI/docs housekeeping (our tests are separate) |
| `ce32558d` | 2026-10-18 | docs(l10n): describe network storage messages | N/A: network storage removed |
| `504c3cd1` | 2026-10-18 | refactor(android): share native album artist resolution | N/A: structural refactor (port rule: port behaviour, not refactors) |
| `08bc4226` | 2026-10-18 | perf(player): cache adjacent track titles during swipes | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `50368012` | 2026-10-18 | refactor(settings): share selectable bottom sheet options | DONE `f609257` (U-515): AppSheetOption.choice with selection semantics |
| `12119530` | 2026-10-18 | refactor(library): share selection action grid layout | N/A: structural refactor (port rule: port behaviour, not refactors) |
| `ad9b2b2e` | 2026-10-18 | refactor(extensions): share priority settings links | N/A: extensions removed |
| `afab47ae` | 2026-10-18 | perf(lyrics): cache timed lyric segment geometry | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `bbeca05a` | 2026-10-18 | perf(releases): narrow weekly release provider dependencies | N/A: online catalogue/home feed removed |
| `e0dfa7eb` | 2026-10-18 | refactor(android): scope Rust download state handles consistently | N/A: downloads removed |
| `dea13177` | 2026-10-18 | refactor(playback): share lost route pause transitions | N/A: structural refactor (port rule: port behaviour, not refactors) |
| `70718b7e` | 2026-10-18 | refactor(ios): share locked backend manager snapshots | N/A: desktop/iOS only |
| `4ab4e87c` | 2026-10-18 | perf(history): reuse unchanged download lookup indexes | N/A: downloads removed |
| `1456d36a` | 2026-10-18 | refactor(downloads): update queue items and indexes together | N/A: downloads removed |
| `579ffae9` | 2026-10-18 | refactor(downloads): centralize failed session accounting | N/A: downloads removed |
| `1b66bc46` | 2026-10-18 | perf(history): suppress unchanged membership notifications | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `bfd18090` | 2026-10-18 | refactor(explore): centralize persistent cache storage | N/A: online catalogue/home feed removed |
| `6b6db4ca` | 2026-10-18 | refactor(settings): migrate remaining sheet choices | DONE `f609257` (U-515): remaining local choice rows use AppSheetOption.choice |
| `75cd4c39` | 2026-10-18 | feat(android): refresh launcher widgets with adaptive expressive layouts | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `2782b1f7` | 2026-10-18 | feat(lyrics): refresh quote sharing and load lyrics on demand | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `f426b2d1` | 2026-10-18 | fix(player): report Android output failures without skipping tracks | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `2455cabc` | 2026-10-18 | fix(haptics): analyze document audio across skips and AutoMix | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `1a6dc736` | 2026-10-18 | feat(home): expose extension country settings and isolate regional caches | N/A: extensions removed |
| `4cee16e9` | 2026-10-18 | feat(home): localize greetings and address profile names | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `9b622f94` | 2026-10-18 | chore(settings): clarify beta features and playback information | DONE `f609257` (U-513): shared BetaBadge (onSurface contrast) on Equalizer, USB bit-perfect and DAP rows; Telegram beta link and external-player text N/A |
| `75907951` | 2026-10-18 | fix(library): restore bit depth as the default quality badge | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `02e67cf3` | 2026-10-18 | feat(library): add adaptive icons to collection tabs | N/A: icons on the Material queue tab chips; our Library uses the Sistrum category rows |
| `080df889` | 2026-10-18 | fix(library): recover missing local album artwork from audio | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `66d480db` | 2026-10-18 | fix(storage): retain legacy Android cipher migration support | N/A: credential storage / verification removed |
| `7c0b275f` | 2026-10-18 | feat(onboarding): introduce the 5.2 release tour | N/A: branding/marketing |
| `2ede99be` | 2026-10-18 | fix(player): restore the lighter full-screen cover scrim | N/A: extensions removed |
| `96dc66f3` | 2026-10-18 | docs(readme): refresh screenshots, badges and feature table | N/A: branding/marketing |
| `67a346c1` | 2026-10-18 | feat(home): greet in the header and gather listening shortcuts | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `0d496acc` | 2026-10-18 | docs(readme): show the redesigned Home screen | N/A: branding/marketing |
| `16cae165` | 2026-10-18 | docs(readme): redesign banner, sections and showcase | N/A: branding/marketing |
| `56ad01ec` | 2026-10-18 | feat(lyrics): add lrc.red and BetterLyrics, split SpotiFLAC-Mobile Lyrics | N/A: online lyrics removed |
| `dbee3d56` | 2026-10-18 | feat(player): search lyrics online for files without them | N/A: online lyrics removed |
| `52ef41f1` | 2026-10-18 | docs(readme): describe the lyrics providers and online search | N/A: release/CI/docs |
| `d63d95db` | 2026-10-18 | fix(lyrics): restore QQ Music search after the desktop CGI broke | N/A: desktop/iOS only |
| `68c739df` | 2026-10-18 | fix(equalizer): keep headroom and limiter choices when applying a preset | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `0810ee78` | 2026-10-18 | refactor(library): drop unread QueueTab page parameters and fast-scroller callbacks | N/A: structural refactor (port rule: port behaviour, not refactors) |
| `acbc614f` | 2026-10-18 | perf(library): build DateFormat and RegExp once instead of per row | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `0539a12f` | 2026-10-18 | ci: add a dart format gate and fix the one drifted test file | N/A: upstream test/CI/docs housekeeping (our tests are separate) |
| `4c78f476` | 2026-10-18 | ci: run the Android Rust build once and cache Cargo | N/A: release/CI/docs |
| `3e86ca14` | 2026-10-18 | docs(contributing): match the repository (l10n, gradle, ffmpeg, test layers) | N/A: release/CI/docs |
| `90631047` | 2026-10-18 | chore: retire Go-era config and rename SMB fixture servers | N/A: network storage removed |
| `95a8802e` | 2026-10-18 | docs(contributing): name every third_party fork and scope the ffmpeg override | N/A: release/CI/docs |
| `5254760b` | 2026-10-18 | build(rust): drop unused direct dependencies and centralize pins | N/A: Cargo workspace pin refactor; our manifests already pin these crates |
| `43f7257d` | 2026-10-18 | docs(rust): say that Go is the retired backend in crate docs | N/A: upstream test/CI/docs housekeeping (our tests are separate) |
| `db85ef05` | 2026-10-18 | docs(rust): mark the Unicode case table as frozen and generated | N/A: upstream test/CI/docs housekeeping (our tests are separate) |
| `7cef0700` | 2026-10-18 | test: split models_and_utils_test by domain and isolate source contracts | N/A: upstream test/CI/docs housekeeping (our tests are separate) |
| `f8f911c9` | 2026-10-18 | chore(analysis): analyze hand-written l10n files and correct the lint comment | N/A: upstream test/CI/docs housekeeping (our tests are separate) |
| `25ad8b3c` | 2026-10-18 | test: poll for cover eviction instead of asserting after one event-loop turn | N/A: upstream test/CI/docs housekeeping (our tests are separate) |
| `77c149eb` | 2026-10-18 | test: skip the automix renderer test when ffmpeg is missing | N/A: upstream test/CI/docs housekeeping (our tests are separate) |
| `e41e6ec4` | 2026-10-18 | test: share one FixedSettingsNotifier across tests | N/A: upstream test/CI/docs housekeeping (our tests are separate) |
| `ec1b84e6` | 2026-10-18 | refactor(services): remove members with no caller | N/A: structural refactor (port rule: port behaviour, not refactors) |
| `48871729` | 2026-10-18 | refactor(services): mark test-only members and privatize file-local ones | N/A: structural refactor (port rule: port behaviour, not refactors) |
| `01925754` | 2026-10-18 | refactor(logging): rename Go-era log names to native | N/A: branding/marketing |
| `6879df49` | 2026-10-18 | refactor(services): clarify misleading names and drop a no-op rethrow | N/A: structural refactor (port rule: port behaviour, not refactors) |
| `5dbf9e6c` | 2026-10-18 | refactor(network): drop the ignored insecure_tls parameter inside Rust | N/A: network storage removed |
| `ef5fa1cb` | 2026-10-18 | perf(lyrics): compile credit regexes once | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `d60baee4` | 2026-10-18 | refactor(rust): restrict test-only functions | N/A: structural refactor (port rule: port behaviour, not refactors) |
| `2debaa53` | 2026-10-18 | refactor(providers): remove the unused Deezer catalogue search | N/A: online catalogue/home feed removed |
| `23c66215` | 2026-10-18 | refactor(bridge): move platform_bridge helpers into part files | N/A: structural refactor (port rule: port behaviour, not refactors) |
| `96568f72` | 2026-10-18 | refactor(library): move queue download labels, dialogs and sliver grid out of queue_tab.dart | N/A: downloads removed |
| `4009855b` | 2026-10-18 | refactor(library): build the filter sheet from the sort-mode table | N/A: structural refactor (port rule: port behaviour, not refactors) |
| `bdb2e636` | 2026-10-18 | refactor(home): move extension collection screens into their own library | N/A: extensions removed |
| `1c7146f9` | 2026-10-18 | refactor(home): split the home tab build into sliver-group builders | N/A: structural refactor (port rule: port behaviour, not refactors) |
| `77377f6b` | 2026-10-18 | refactor(metadata): one option picker for provider and cover size | N/A: structural refactor (port rule: port behaviour, not refactors) |
| `714bec6a` | 2026-10-18 | refactor(metadata): split the edit sheet into cover and auto-fill parts | N/A: structural refactor (port rule: port behaviour, not refactors) |
| `237690cd` | 2026-10-18 | refactor(metadata): move editor form primitives into a widgets file | N/A: structural refactor (port rule: port behaviour, not refactors) |
| `77c8639d` | 2026-10-18 | refactor(lyrics): split player_lyrics.dart into line-style and word-sweep parts | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `8fd574f0` | 2026-10-18 | refactor(rewind): split the listening rewind screen and move its providers | N/A: refactor of listening rewind (no behaviour change) |
| `e9834f06` | 2026-10-18 | refactor(equalizer): split the equalizer screen into widgets and curve parts | N/A: structural refactor (port rule: port behaviour, not refactors) |
| `12ff0990` | 2026-10-18 | refactor(setup): move the setup step builders into a part | N/A: structural refactor (port rule: port behaviour, not refactors) |
| `b64b08c4` | 2026-10-18 | refactor(shell): move nav icons to a widget file and startup prompts into a part | N/A: structural refactor (port rule: port behaviour, not refactors) |
| `ca950dc3` | 2026-10-18 | refactor(android): remove backend switches that became constants | N/A: structural refactor (port rule: port behaviour, not refactors) |
| `8aca5e4e` | 2026-10-18 | refactor(android): drop unreachable dispatch cases and dead channel handlers | N/A: structural refactor (port rule: port behaviour, not refactors) |
| `fcec0942` | 2026-10-18 | refactor(android): drop SDK checks below minSdk 24 | N/A: structural refactor (port rule: port behaviour, not refactors) |
| `92adce43` | 2026-10-18 | refactor(native): share errorJson and retire Go-era names in native comments | N/A: structural refactor (port rule: port behaviour, not refactors) |
| `3f904004` | 2026-10-18 | refactor(rust): move inline tests and the test-only hires decoder into submodules | N/A: structural refactor (port rule: port behaviour, not refactors) |
| `a6dda023` | 2026-10-18 | refactor(lyrics): split native_lyrics into text, lrc, ttml, credits and tests modules | N/A: structural refactor (port rule: port behaviour, not refactors) |
| `c2b7a0b7` | 2026-10-18 | refactor(downloads): move pure queue policy helpers into download_queue_policy.dart | N/A: downloads removed |
| `fbed4960` | 2026-10-18 | refactor(history): move the history schema and row mapper into their own files | N/A: structural refactor (port rule: port behaviour, not refactors) |
| `eeb010cd` | 2026-10-18 | refactor(library): extract the ingestion store from library_database.dart | N/A: extensions removed |
| `1b2efc76` | 2026-10-18 | refactor(extensions): split runtime.rs into control, vm and tests modules | N/A: extensions removed |
| `380b5cb8` | 2026-10-18 | refactor(extensions): split backend/downloads.rs helpers into submodules and move its sibling tests | N/A: downloads removed |
| `d0cdaafc` | 2026-10-18 | refactor(settings): move extension_detail_page widgets into a part | N/A: extensions removed |
| `f3e44f3e` | 2026-10-18 | refactor(settings): move library_settings_page widgets into a part | N/A: structural refactor (port rule: port behaviour, not refactors) |
| `486fd3b6` | 2026-10-18 | refactor(settings): move download_settings_page widgets into a part | N/A: downloads removed |
| `a3961eef` | 2026-10-18 | refactor(settings): move files_settings_page widgets into a part | N/A: structural refactor (port rule: port behaviour, not refactors) |
| `6e43c036` | 2026-10-18 | refactor(settings): move appearance_settings_page widgets into a part | N/A: structural refactor (port rule: port behaviour, not refactors) |
| `0d2fef4c` | 2026-10-18 | refactor(settings): move extensions_page widgets into a part | N/A: extensions removed |
| `95666c10` | 2026-10-18 | refactor(settings): move log_screen widgets into a part | N/A: structural refactor (port rule: port behaviour, not refactors) |
| `992e21e2` | 2026-10-18 | refactor(player): port tests to musicPlayerRuntime and delete the test-only wrappers | N/A: structural refactor (port rule: port behaviour, not refactors) |
| `548567ef` | 2026-10-18 | refactor(player): move PlayableMedia to playable_media.dart | N/A: structural refactor (port rule: port behaviour, not refactors) |
| `92d655fd` | 2026-10-18 | refactor(player): move restorePlaybackSession to playback_session_restore.dart | N/A: extensions removed |
| `12d422af` | 2026-10-18 | refactor(extensions): split manager.rs into install, lifecycle, info and tests modules | N/A: extensions removed |
| `42c90dbf` | 2026-10-18 | refactor(network): split client.rs into pool, stream, headers and tests, and factor execute_stream | N/A: network storage removed |
| `92af56ee` | 2026-10-18 | refactor(android): move finalizer decrypt into NativeFinalizerDecrypt.kt | N/A: downloads removed |
| `ead04c00` | 2026-10-19 | refactor(android): move finalizer container into NativeFinalizerContainer.kt | N/A: downloads removed |
| `0b4725c2` | 2026-10-19 | refactor(android): move finalizer metadata into NativeFinalizerMetadata.kt | N/A: downloads removed |
| `631b9aa5` | 2026-10-19 | refactor(android): move finalizer post-processing into NativeFinalizerPostProcess.kt | N/A: downloads removed |
| `b5cf9788` | 2026-10-19 | refactor(android): move finalizer history into NativeFinalizerHistory.kt | N/A: downloads removed |
| `07970853` | 2026-10-19 | refactor(io): use deleteFileQuietly for exists-then-delete | N/A: structural refactor (port rule: port behaviour, not refactors) |
| `d6fd05c3` | 2026-10-19 | refactor(io): use isContentUri instead of inline content:// checks | N/A: structural refactor (port rule: port behaviour, not refactors) |
| `036589a4` | 2026-10-19 | refactor(notifications): reuse formatMegabytes | N/A: structural refactor (port rule: port behaviour, not refactors) |
| `adf2047d` | 2026-10-19 | refactor(utils): share the FNV-1a 32-bit hash | N/A: structural refactor (port rule: port behaviour, not refactors) |
| `cc9b9f11` | 2026-10-19 | test(android): assert the backend routing set matches the dispatch cases | N/A: upstream test/CI/docs housekeeping (our tests are separate) |
| `b6b609f3` | 2026-10-19 | refactor(android): move Impeller helpers, the SAF tree picker and progress streams out of MainActivity.kt | N/A: structural refactor (port rule: port behaviour, not refactors) |
| `20b4c73b` | 2026-10-19 | refactor(android): move RustCoreBackend.invokeApplication into its own file | N/A: structural refactor (port rule: port behaviour, not refactors) |
| `ff3f7520` | 2026-10-19 | refactor(metadata): share the sidecar publish path between save-cover and save-lyrics | N/A: structural refactor (port rule: port behaviour, not refactors) |
| `088bd875` | 2026-10-19 | refactor(core): move the lenient Go-style JSON decoder to core::json | N/A: structural refactor (port rule: port behaviour, not refactors) |
| `f7a15cbd` | 2026-10-19 | refactor(rust): consolidate small duplicate helpers | N/A: structural refactor (port rule: port behaviour, not refactors) |
| `190801c3` | 2026-10-19 | refactor(core): add fs::write_atomic and use it for the atomic file writes | N/A: refactor to core::fs::write_atomic with identical publication order |
| `ab8a329d` | 2026-10-19 | refactor(layering): move UI action helpers from services and utils to controllers | N/A: structural refactor (port rule: port behaviour, not refactors) |
| `ce21896f` | 2026-10-19 | refactor(layering): move model files to models and fix inverted imports | N/A: structural refactor (port rule: port behaviour, not refactors) |
| `99ccc882` | 2026-10-19 | refactor(layering): move logic files out of screens | N/A: structural refactor (port rule: port behaviour, not refactors) |
| `1521c495` | 2026-10-19 | docs(selection): correct the SelectionModeMixin doc | N/A: upstream test/CI/docs housekeeping (our tests are separate) |
| `78799e1b` | 2026-10-19 | refactor(layout): share responsiveScale and effectiveTextScale | N/A: structural refactor (port rule: port behaviour, not refactors) |
| `4598773c` | 2026-10-19 | refactor(storage): share the SAF download tree pick | N/A: downloads removed |
| `263a1017` | 2026-10-19 | refactor(home): use downloadSingleTrack for search results | N/A: downloads removed |
| `485be2f4` | 2026-10-19 | refactor(artist): move the discography download into a part | N/A: downloads removed |
| `fe29f304` | 2026-10-19 | refactor(playlists): share the playlist name prompt and dispose its controller | N/A: our playlist name prompt already disposes its controllers in try/finally |
| `da2fc2c9` | 2026-10-19 | refactor(extensions): share the extension health color and icon helpers | N/A: extensions removed |
| `b10370e4` | 2026-10-19 | refactor(share): share the widget capture helper | N/A: structural refactor (port rule: port behaviour, not refactors) |
| `ba376d69` | 2026-10-19 | refactor(repo): prepare install paths in the repo notifier | N/A: extensions removed |
| `bff5123c` | 2026-10-19 | refactor(concerts): move the calendar channel into a service | N/A: online catalogue/home feed removed |
| `affa6314` | 2026-10-19 | refactor(rust): rename mod.rs modules to the foo.rs + foo/ layout | N/A: branding/marketing |
| `c10c0ab5` | 2026-10-19 | docs(rust): add module docs to large modules without one | N/A: upstream test/CI/docs housekeeping (our tests are separate) |
| `8af7efb6` | 2026-10-19 | refactor(providers): move UI-declared providers to lib/providers | N/A: structural refactor (port rule: port behaviour, not refactors) |
| `76288006` | 2026-10-19 | refactor(setup): move SharedPreferences access behind SetupProgressStore and SafMigrationPromptStore | N/A: extensions removed |
| `34a004f9` | 2026-10-19 | refactor(analysis): move the pure FFmpeg builders and parsers to a service | N/A: structural refactor (port rule: port behaviour, not refactors) |
| `b575a4ea` | 2026-10-19 | refactor(analysis): move the analysis disk cache into audio_analysis_cache.dart | N/A: structural refactor (port rule: port behaviour, not refactors) |
| `755c9079` | 2026-10-19 | refactor(analysis): move the FFmpeg runner out of the widget | N/A: structural refactor (port rule: port behaviour, not refactors) |
| `8fffb923` | 2026-10-19 | refactor(cache): move directory scanning and clearing into CacheMaintenanceService | N/A: structural refactor (port rule: port behaviour, not refactors) |
| `857c2954` | 2026-10-19 | refactor(collections): move playlist cover file I/O into PlaylistCoverStore | N/A: extensions removed |
| `db4643c2` | 2026-10-19 | refactor(bridge): share one generic cache entry and put/prune helper | N/A: structural refactor (port rule: port behaviour, not refactors) |
| `830dee31` | 2026-10-19 | refactor(queue): move library paging state into QueueLibraryPager | N/A: structural refactor (port rule: port behaviour, not refactors) |
| `5b3a2b95` | 2026-10-19 | refactor(queue): move the completion bridge into CompletionBridgeTracker | N/A: structural refactor (port rule: port behaviour, not refactors) |
| `c1c7d421` | 2026-10-19 | refactor(convert): route single-track conversion through the shared pipeline | N/A: structural refactor (port rule: port behaviour, not refactors) |
| `b0600c1f` | 2026-10-19 | refactor(library): remove the unreachable snapshot sub-branch of the incremental scan | N/A: structural refactor (port rule: port behaviour, not refactors) |
| `de142aba` | 2026-10-19 | refactor(library): share the scan completion tail as _finishScan | N/A: structural refactor (port rule: port behaviour, not refactors) |
| `ff7afa5b` | 2026-10-19 | refactor(library): split local_library_provider.dart into source, scan and cover parts | N/A: structural refactor (port rule: port behaviour, not refactors) |
| `cf4c05cd` | 2026-10-19 | refactor(android): move install state, extension intents, SAF leases and small channels out of MainActivity.kt | N/A: extensions removed |
| `01c51bf7` | 2026-10-19 | refactor(android): move the SAF backend calls into MainActivitySafCalls.kt | N/A: structural refactor (port rule: port behaviour, not refactors) |
| `5d0f2744` | 2026-10-19 | refactor(android): move the metadata and tag backend calls into MainActivityMetadataCalls.kt | N/A: structural refactor (port rule: port behaviour, not refactors) |
| `cbf41441` | 2026-10-19 | refactor(android): move the library scan backend calls into MainActivityLibraryScanCalls.kt | N/A: structural refactor (port rule: port behaviour, not refactors) |
| `00b661be` | 2026-10-19 | refactor(android): move the download service and worker backend calls into MainActivityServiceCalls.kt | N/A: downloads removed |
| `f88217dd` | 2026-10-19 | refactor(android): move the lifecycle backend calls into MainActivityLifecycleCalls.kt | N/A: structural refactor (port rule: port behaviour, not refactors) |
| `4557e361` | 2026-10-19 | chore(l10n): remove 63 unused localization keys | TRANSLATION: l10n housekeeping (pending translation import batch) |
| `4791f55a` | 2026-10-19 | refactor(providers): share one Coalescer for single-flight request coalescing | N/A: structural refactor (port rule: port behaviour, not refactors) |
| `071d72b2` | 2026-10-19 | refactor(android): share the foreground wake lock and start helper between the two services | N/A: structural refactor (port rule: port behaviour, not refactors) |
| `a19a5287` | 2026-10-19 | refactor(android): put the SAF IO helpers on Context receivers | N/A: structural refactor (port rule: port behaviour, not refactors) |
| `202923fb` | 2026-10-19 | test(android): pin the extension and MIME tables | N/A: extensions removed |
| `c7cccd4e` | 2026-10-19 | test(bridge): inject the lookup cache persist debounce | N/A: upstream test/CI/docs housekeeping (our tests are separate) |
| `31999a15` | 2026-10-19 | test(player): drive AutoMix transport and haptics with fake time | N/A: upstream test/CI/docs housekeeping (our tests are separate) |
| `8ef3bca6` | 2026-10-19 | test(queue): remove real waits from the startup flush test | N/A: upstream test/CI/docs housekeeping (our tests are separate) |
| `fe60a8ac` | 2026-10-19 | test(player): split music_player_automix_test.dart by group | N/A: upstream test/CI/docs housekeeping (our tests are separate) |
| `461e449e` | 2026-10-19 | refactor(android): move SAF file inspection out of MainActivitySafScan.kt | N/A: structural refactor (port rule: port behaviour, not refactors) |
| `bb930827` | 2026-10-19 | refactor(android): move SAF scan checkpointing out of MainActivitySafScan.kt | N/A: structural refactor (port rule: port behaviour, not refactors) |
| `2af0fa95` | 2026-10-19 | refactor(android): move SAF CUE helpers out of MainActivitySafScan.kt | N/A: structural refactor (port rule: port behaviour, not refactors) |
| `671b5a25` | 2026-10-19 | refactor(android): move SAF tree listing and executors out of MainActivitySafScan.kt | N/A: structural refactor (port rule: port behaviour, not refactors) |
| `eeda9553` | 2026-10-19 | refactor(android): move SAF batch exists and modtime queries out of MainActivitySafScan.kt | N/A: structural refactor (port rule: port behaviour, not refactors) |
| `e80ae1b1` | 2026-10-19 | refactor(android): share the SAF scan percent and CUE helpers | N/A: structural refactor (port rule: port behaviour, not refactors) |
| `a70abf8f` | 2026-10-19 | docs(android): document the native channel contract | N/A: release/CI/docs |
| `7d2c1e6a` | 2026-10-19 | docs(integration-test): index the device suites and their defines | N/A: release/CI/docs |
| `00d476c1` | 2026-10-19 | docs(rust): describe the backend workspace, builds and bindings | N/A: release/CI/docs |
| `44cbd453` | 2026-10-19 | docs(third-party): complete the vendored plugin patch notes | N/A: release/CI/docs |
| `c4cf56fb` | 2026-10-19 | docs(theme): explain the Material and Sistrum theme layer | N/A: release/CI/docs |
| `c6f8ac21` | 2026-10-19 | docs(test): describe test layout, contracts and host tools | N/A: release/CI/docs |
| `d3a51a6a` | 2026-10-19 | docs(contributing): add the codebase map and architecture guide | N/A: release/CI/docs |
| `1bc8c05e` | 2026-10-19 | fix(downloads): offer folder recovery for permission failures | N/A: downloads removed |
| `fbaf7fa4` | 2026-10-19 | feat(about): link the lyrics website and service status | N/A: online lyrics removed |
| `18fd5568` | 2026-10-19 | chore(lyrics): rename first-party provider to Zarz-LRC | N/A: online lyrics removed |
| `378c8f37` | 2026-10-19 | fix(library): recover interrupted scans and stale notifications | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `cb51d089` | 2026-10-19 | feat(crash): show persistent crash reports on Home | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `36694c6e` | 2026-10-19 | fix(crash): match the Home crash card to the error card style | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `55d85c4a` | 2026-10-19 | docs(readme): drop heading anchors from feature cards | N/A: release/CI/docs |
| `21ee30c4` | 2026-10-19 | chore: update AltStore source to v5.2.0 | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `205e178e` | 2026-10-19 | fix(android): apply renderer compatibility before shared engine creation | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `e58217c8` | 2026-10-19 | fix(library): release network scan memory and cancel active metadata reads | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `27a45c04` | 2026-10-19 | fix(backup): reconcile restored iOS paths before publishing history | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `931b1091` | 2026-10-19 | fix(crash): exclude system memory kills from crash notices | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `9dc86e13` | 2026-10-19 | fix(artwork): read padded ID3 covers and repair cached previews | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `a3b14a28` | 2026-10-19 | fix(downloads): embed enriched artwork across audio formats | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `721a3fa7` | 2026-10-20 | feat(ui): align Material screens with M3 Expressive guidance | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `9acaa760` | 2026-10-20 | fix(haptics): render music pulses on basic motors and add tuning sliders | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `91add520` | 2026-10-20 | fix(lyrics): ease synced line changes with a spring scroll | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `19056edf` | 2026-10-20 | perf(library): cache unchanged SMB and WebDAV scan metadata | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `b946c373` | 2026-10-20 | fix(home): show listening sections on the Sistrum Home without a feed | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `9eea6a1a` | 2026-10-20 | feat(playback): add normalization pre-amp and track or album gain | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `d6c6940e` | 2026-10-20 | chore(release): bump app to 5.2.1 build 163 | N/A: release bookkeeping |
| `37162363` | 2026-10-20 | feat(player): swipe up on the mini player to open Now Playing | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `1829363d` | 2026-10-20 | fix(home): match On repeat tracks to their Library entry | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `9ded49f3` | 2026-10-20 | fix(player): refresh late duration updates without reopening | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `5ecbb7ac` | 2026-10-20 | fix(concerts): give the Material concert page a Material layout | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `ba234d78` | 2026-10-20 | fix(ui): align Material screens with the design guide | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `b279733a` | 2026-10-20 | fix(library): use path index for network scan cache lookups | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `d7798898` | 2026-10-20 | fix(startup): wait for the Activity before backend startup calls | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `60d00191` | 2026-10-20 | fix(player): prefer embedded art for local files over online covers | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `00b7cf99` | 2026-10-20 | fix(crash): reduce repeated notices and retain diagnostics | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `7600c169` | 2026-10-20 | perf(ui): improve Material and Sistrum player and library smoothness | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `37e21b57` | 2026-10-20 | feat(branding): rename app and native backend to Sistrum | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `243fee8c` | 2026-10-20 | docs(readme): remove Related Projects section | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `51d34594` | 2026-10-20 | chore(branding): drop remaining SpotiFLAC references | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `f72fe69e` | 2026-10-20 | feat(branding): adopt the Sistrum logo across the app | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `ae728525` | 2026-10-20 | feat(branding): use Sistrum Ink for the iOS launch screen | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `8e4504e7` | 2026-10-20 | feat(onboarding): replace the 5.2 tour with a rebrand tour | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `f70bc955` | 2026-10-20 | feat(desktop): add generated macOS, Windows and Linux runners | N/A: desktop/iOS only |
| `f10c9d88` | 2026-10-20 | feat(desktop): set Sistrum identity, icons, window size and entitlements | N/A: desktop/iOS only |
| `840e16e1` | 2026-10-20 | feat(desktop): add desktop platform check, scroll and theme defaults | N/A: desktop/iOS only |
| `e0563ffa` | 2026-10-20 | chore: update AltStore source to v5.2.1 | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `4396e894` | 2026-10-20 | feat(desktop): add the isDesktopPlatform check | N/A: desktop/iOS only |
| `f502edd1` | 2026-10-20 | feat(desktop): route the backend channel through Rust FFI on desktop | N/A: desktop/iOS only |
| `6aeed936` | 2026-10-20 | feat(desktop): use plain folders and SQLite FFI on desktop | N/A: desktop/iOS only |
| `840b28d5` | 2026-10-20 | feat(desktop): enable notifications and gate mobile-only plugins | N/A: desktop/iOS only |
| `a86bcd01` | 2026-10-20 | fix(desktop): report the desktop platform to native jobs and logs | N/A: desktop/iOS only |
| `cbc2c312` | 2026-10-20 | feat(desktop): add Rust C ABI backend crate | N/A: desktop/iOS only |
| `40f6f0b3` | 2026-10-20 | build(desktop): stage the desktop library from build_rust_backend.sh | N/A: desktop/iOS only |
| `067b1b69` | 2026-10-20 | test(desktop): smoke test the Rust FFI backend on a desktop host | N/A: desktop/iOS only |
| `e1b4b48b` | 2026-10-20 | fix(rust): gate unix filesystem calls for Windows builds | N/A: desktop/iOS only |
| `86dbc2fe` | 2026-10-20 | feat(core): read the local time zone on Windows | N/A: desktop/iOS only |
| `ea75721d` | 2026-10-20 | fix(extensions): confine extension files and packages on Windows | N/A: desktop/iOS only |
| `dd513d8f` | 2026-10-20 | build(desktop): bundle the Rust library into the macOS app | N/A: desktop/iOS only |
| `5d369a26` | 2026-10-20 | build(desktop): install the Rust library in the Linux and Windows bundles | N/A: desktop/iOS only |
| `02f3cb99` | 2026-10-20 | ci(desktop): build the macOS, Linux and Windows apps | N/A: release/CI/docs |
| `375a489a` | 2026-10-20 | test(desktop): document the bundled library in the smoke test | N/A: desktop/iOS only |
| `8b90b1b3` | 2026-10-20 | feat(desktop): add the desktop shell with rail, sidebar and player bar | N/A: desktop/iOS only |
| `dea5a0c0` | 2026-10-20 | test(desktop): cover the desktop shell, player bar and shortcuts | N/A: desktop/iOS only |
| `fb4f4574` | 2026-10-20 | feat(desktop): run FFmpeg and ffprobe through bundled executables | N/A: desktop/iOS only |
| `e0669f7c` | 2026-10-20 | build(desktop): add script to stage LGPL ffmpeg and ffprobe | N/A: desktop/iOS only |
| `4431f25f` | 2026-10-20 | docs(licenses): add the FFmpeg LGPL notice and source offer | DONE `eb44a8e` (U-511): FFmpeg (FFmpegKit) LGPL notice and source offer on the licence page; desktop FFmpeg excluded |
| `e9849b6b` | 2026-10-20 | feat(playback): add a PlaybackDeck seam and enable the macOS equalizer | N/A: desktop/iOS only |
| `fe32c727` | 2026-10-20 | test(playback): play a generated tone through the macOS deck | N/A: desktop/iOS only |
| `767edb37` | 2026-10-20 | build(packaging): add dmg, AppImage, deb and Inno Setup packaging | N/A: desktop packaging |
| `173555a1` | 2026-10-20 | ci(release): build and publish desktop packages | N/A: release/CI/docs |
| `2411450a` | 2026-10-20 | feat(update): update desktop builds from their release packages | N/A: desktop/iOS only |
| `c8191200` | 2026-10-20 | build(ffmpeg): build a universal LGPL FFmpeg with soxr for macOS | N/A: desktop/iOS only |
| `dbb59e7a` | 2026-10-20 | build(desktop): bundle the staged ffmpeg and ffprobe in desktop apps | N/A: desktop/iOS only |
| `d99a7a6c` | 2026-10-20 | docs(licenses): add the LGPL 3.0 text for FFmpegKit and desktop FFmpeg | DONE `eb44a8e` (U-511): LGPL 3.0 text for FFmpegKit |
| `e8706589` | 2026-10-20 | ci(desktop): stage and verify the bundled LGPL FFmpeg | N/A: release/CI/docs |
| `7855428e` | 2026-10-20 | ci(release): bundle the LGPL FFmpeg in desktop release packages | N/A: release/CI/docs |
| `0aeeeeb7` | 2026-10-20 | feat(desktop): add keep-awake, Discord IPC, folder watching and panic log to the Rust backend | N/A: desktop/iOS only |
| `490e5292` | 2026-10-20 | feat(desktop): wire deep links, single instance, keep-awake, Discord, watcher and crash logs | N/A: desktop/iOS only |
| `0c0272ff` | 2026-10-20 | fix(desktop): end the diagnostics session before an update quits | N/A: desktop/iOS only |
| `7cc40175` | 2026-10-20 | test(desktop): close stream controllers and drop an unused import | N/A: desktop/iOS only |
| `43039565` | 2026-10-20 | feat(desktop): present app sheets as centered dialogs | N/A: desktop/iOS only |
| `9d6785c8` | 2026-10-20 | feat(desktop): center setup and tutorial in a desktop column | N/A: desktop/iOS only |
| `b52a4078` | 2026-10-20 | feat(desktop): show settings as a list-detail layout | N/A: desktop/iOS only |
| `8acabd67` | 2026-10-20 | feat(desktop): let the extension store grid fill the pane | N/A: desktop/iOS only |
| `003b2cff` | 2026-10-20 | feat(desktop): open Now Playing in the content pane with an inspector | N/A: desktop/iOS only |
| `6735f5dc` | 2026-10-20 | fix(settings): align the extension overview with its settings groups on wide panes | N/A: extensions removed |
| `5f903b2a` | 2026-10-20 | fix(desktop): keep extension storage migration out of the user's Documents | N/A: desktop/iOS only |
| `c57de023` | 2026-10-20 | fix(desktop): pass the app version to the Rust backend | N/A: desktop/iOS only |
| `6b4f81d8` | 2026-10-20 | feat(desktop): turn on the core backend and extension system | N/A: desktop/iOS only |
| `bcb1ee8b` | 2026-10-20 | feat(desktop): play through media_kit with MPRIS and SMTC sessions | N/A: desktop/iOS only |
| `f3c05dfb` | 2026-10-20 | build(macos): sign with a stable self-signed identity when available | N/A: desktop/iOS only |
| `95a11dbd` | 2026-10-20 | fix(desktop): report crashes only with evidence and keep one macOS instance | N/A: desktop/iOS only |
| `4f16428c` | 2026-10-20 | feat(desktop): add hover scroll buttons to Home shelves | N/A: desktop/iOS only |
| `d83d2a7c` | 2026-10-20 | fix(settings): keep the profile page open after Save in the desktop pane | N/A: desktop/iOS only |
| `728c1a1a` | 2026-10-20 | feat(desktop): add context menus, list selection and a song table | N/A: desktop/iOS only |
| `c654de57` | 2026-10-20 | feat(desktop): show detail screen songs as a sortable table | N/A: desktop/iOS only |
| `87c92c8d` | 2026-10-20 | feat(desktop): add Library context menus, song table and hover play | N/A: desktop/iOS only |
| `5e16cf0e` | 2026-10-20 | feat(desktop): add context menus to artist, home and search rows | N/A: desktop/iOS only |
| `382e3856` | 2026-10-20 | feat(desktop): add dropped music folders to the Library | N/A: desktop/iOS only |
| `ef0bb0d4` | 2026-10-20 | feat(desktop): keep album play buttons in the song table | N/A: desktop/iOS only |
| `2b4625f3` | 2026-10-20 | fix(desktop): keep download rows in the queue header's column | N/A: desktop/iOS only |
| `7b94fe17` | 2026-10-20 | feat(desktop): compact detail headers and denser song rows | N/A: desktop/iOS only |
| `ddb89791` | 2026-10-20 | feat(desktop): Apple Music style album, playlist and artist headers | N/A: desktop/iOS only |
| `654dc01c` | 2026-10-20 | fix(desktop): keep the profile photo in the app support folder | N/A: desktop/iOS only |
| `fa035bd1` | 2026-10-20 | feat(desktop): keep the Apple Music artist hero in Sistrum | N/A: desktop/iOS only |
| `ff5001df` | 2026-10-20 | feat(desktop): Apple Music style macOS shell | N/A: desktop/iOS only |
| `77e4a421` | 2026-10-20 | fix(settings): select Sistrum desktop categories with a quiet gray fill | N/A: desktop/iOS only |
| `a7faaff2` | 2026-10-20 | feat(desktop): lay out the Sistrum player capsule like Music | N/A: desktop/iOS only |
| `0bba1158` | 2026-10-20 | fix(desktop): drop the Material search bar and widen rail pills | N/A: desktop/iOS only |
| `8eaa7e3e` | 2026-10-20 | fix(desktop): run Home's feed across the whole content pane | N/A: desktop/iOS only |
| `8fcc4183` | 2026-10-20 | fix(desktop): switch theme styles without remounting the app | N/A: desktop/iOS only |
| `504b6617` | 2026-10-20 | fix(desktop): give every page the same full-pane width | N/A: desktop/iOS only |
| `4f610409` | 2026-10-20 | feat(settings): group Material desktop categories as connected lists | N/A: desktop/iOS only |
| `47098697` | 2026-10-20 | fix(onboarding): leave the former app name out of the tour | N/A: branding/marketing |
| `ee5d1254` | 2026-10-20 | feat(desktop): morph the Material rail and let it be collapsed | N/A: desktop/iOS only |
| `82b2961b` | 2026-10-21 | fix(desktop): line the rail menu icon up with the destinations | N/A: desktop/iOS only |
| `6bbc0823` | 2026-10-21 | fix(library): recognize NAS connection aliases in duplicate review | N/A: network storage removed |
| `faa08f5b` | 2026-10-21 | fix(library): prune stale NAS rows outside failed scan paths | N/A: network storage removed |
| `2d814d5b` | 2026-10-21 | test(playlists): cover scrolling a large local collection | N/A: upstream test/CI/docs housekeeping (our tests are separate) |
| `c9732fe4` | 2026-10-21 | fix(downloads): keep finalized FLAC paths and container names consistent | N/A: downloads removed |
| `b6c996ef` | 2026-10-21 | fix(desktop): let macOS and Linux pick library folders | N/A: desktop/iOS only |
| `23e531e7` | 2026-10-21 | fix(desktop): round Sistrum detail artwork with continuous corners | N/A: desktop/iOS only |
| `199024f5` | 2026-10-21 | fix(metadata): center the Sistrum quality row and header buttons | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `f5741123` | 2026-10-21 | fix(library): open song details on a desktop click | N/A: desktop/iOS only |
| `02e50bd0` | 2026-10-21 | fix(desktop): play or open a row on a single click | N/A: desktop/iOS only |
| `0a963a28` | 2026-10-21 | fix(desktop): keep the selection bar over the pages and bounded | N/A: desktop/iOS only |
| `435afff4` | 2026-10-21 | fix(desktop): keep the Sistrum sidebar in every window size | N/A: desktop/iOS only |
| `6a3e9ab7` | 2026-10-21 | fix(lyrics): reach far lines taller than the Material row estimate | DONE `78cac12` (U-510): regression test only; our scroll already reaches the far line, the upstream scroll change regressed extreme cases here |
| `afaca0f1` | 2026-10-21 | feat(desktop): show Now Playing over the whole window, as Music does | N/A: desktop/iOS only |
| `38659c02` | 2026-10-21 | fix(playback): seek FLAC accurately on macOS and iOS | N/A: desktop/iOS only |
| `5f4bb7cc` | 2026-10-21 | fix(lyrics): keep line timers aligned with playback | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `2a9daecf` | 2026-10-21 | fix(lyrics): match lrc.red recordings and collaborators | N/A: online lyrics removed |
| `3c7edf6f` | 2026-10-21 | chore(branding): point links and packaging at upstream repository | N/A: branding/marketing |
| `f6df8502` | 2026-10-21 | feat(release): publish desktop builds in upstream repository-Desktop | N/A: desktop/iOS only |
| `d04bd9ea` | 2026-10-21 | fix(settings): line extension links up with the other rows | N/A: extensions removed |
| `a3c4e3f5` | 2026-10-21 | feat(desktop): start the Material rail collapsed without a menu button | N/A: desktop/iOS only |
| `ea9e8639` | 2026-10-21 | fix(desktop): line the album header artwork up with the content | N/A: desktop/iOS only |
| `01d76640` | 2026-10-21 | fix(metadata): enlarge the desktop cover and show the lyrics box scrolls | N/A: desktop/iOS only |
| `56e51f0b` | 2026-10-21 | fix(player): stretch the desktop Material transport to the timeline | N/A: desktop/iOS only |
| `306ea4f3` | 2026-10-21 | fix(lyrics): size Material lyrics for the desktop panel | N/A: desktop/iOS only |
| `33848427` | 2026-10-21 | fix(library): start desktop grid covers larger | N/A: desktop/iOS only |
| `af500a73` | 2026-10-21 | feat(lyrics): choose lyrics from each provider in the metadata editor | N/A: online lyrics removed |
| `be5c1843` | 2026-10-21 | feat(search): lay out the Sistrum desktop Search page like Music | N/A: desktop/iOS only |
| `69011f48` | 2026-10-21 | fix(desktop): skip the held liquid lens on Sistrum segmented controls | N/A: desktop/iOS only |
| `c7d22b05` | 2026-10-21 | fix(library): give the Sistrum overview rows their own Material | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `b532cb5d` | 2026-10-21 | fix(lyrics): drop singer marks from lyrics picker previews | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `400a7604` | 2026-10-21 | fix(desktop): shape loading skeletons like the loaded tables | N/A: desktop/iOS only |
| `60322186` | 2026-10-21 | fix(shell): keep the open tab when switching styles | N/A: switching theme styles; Sistrum is the only style |
| `ca189a90` | 2026-10-21 | feat(desktop): animate the lyrics and Up Next panels open and closed | N/A: desktop/iOS only |
| `53dfa2c3` | 2026-10-21 | fix(desktop): hide scrollbars where they add clutter | N/A: desktop/iOS only |
| `37356e43` | 2026-10-21 | fix(player): skip tracks with mini player swipes | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `fc7e73fe` | 2026-10-21 | fix(player): preserve audio information from track metadata | N/A: only TrackMetadataScreen called playLocalPath; that screen is removed here |
| `acb826da` | 2026-10-21 | ci(desktop): pin Windows to VS 2022 and unblock GStreamer on Linux | N/A: release/CI/docs |
| `876d4a47` | 2026-10-21 | fix(library): keep scanning when a row has no scan time or is invalid | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `08f5fa64` | 2026-10-21 | fix(desktop): bind Discord presence to the player | N/A: desktop/iOS only |
| `a428b378` | 2026-10-21 | feat(i18n): mirror layouts for right-to-left languages | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `1a13bc2e` | 2026-10-21 | fix(equalizer): wrap presets on desktop instead of clipping them | N/A: desktop/iOS only |
| `ea854078` | 2026-10-21 | feat(playlist): add a shuffle button to the playlist header | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `aca88293` | 2026-10-21 | feat(settings): show donation progress on the desktop Settings row | N/A: desktop/iOS only |
| `daaafbc7` | 2026-10-21 | fix(desktop): register sistrum:// from portable and AppImage copies | N/A: desktop/iOS only |
| `be50a4db` | 2026-10-21 | fix(settings): close the orphan cleanup dialog from its own navigator | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `4a3805a5` | 2026-10-21 | build(desktop): move bundled FFmpeg to 9.0 | N/A: desktop/iOS only |
| `fcdd898f` | 2026-10-21 | fix(backup): preserve extension repository for automatic restore | N/A: extensions removed |
| `d7d48ba2` | 2026-10-21 | fix(metadata): let the lyrics box span the card | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `6af4e585` | 2026-10-21 | fix(player): keep the no-lyrics state above the Sistrum controls | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `54404cdf` | 2026-10-21 | fix(desktop): open the Downloads page from the downloads popover | N/A: desktop/iOS only |
| `cba77c1f` | 2026-10-21 | fix(history): use single-quoted empty strings in path queries | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `268de6ee` | 2026-10-21 | fix(windows): pin flutter_rust_bridge to the version smtc_windows uses | N/A: desktop/iOS only |
| `c1859530` | 2026-10-21 | chore(release): bump app to 5.2.5 build 164 | N/A: release bookkeeping |
| `6f2498b9` | 2026-10-21 | ci(desktop): build the Linux bundle for arm64 as well | N/A: release/CI/docs |
| `cc12080a` | 2026-10-21 | fix(android): avoid Samsung Vulkan crash on SM-S711B Android 16 | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `1ef604e6` | 2026-10-21 | feat(extensions): enable newly installed extensions by default | N/A: extensions removed |
| `b4751c29` | 2026-10-21 | fix(linux): build FFmpegKit without its bundle on arm64 | N/A: desktop/iOS only |
| `909a70c1` | 2026-10-21 | fix(desktop): present Material song menus and sheets as desktop surfaces | N/A: desktop/iOS only |
| `d6602570` | 2026-10-21 | feat(desktop): tighten Material density for pointer input | N/A: desktop/iOS only |
| `f74076ab` | 2026-10-21 | feat(desktop): list keyboard shortcuts in Settings | N/A: desktop/iOS only |
| `62a9e468` | 2026-10-21 | fix(library): look up artists in the search provider for downloads | N/A: downloads removed |
| `5bf92542` | 2026-10-21 | feat(desktop): list the Library Songs tab in the songs table | N/A: desktop/iOS only |
| `bc6e2e7b` | 2026-10-21 | feat(material): give each surface role one meaning | N/A: Material / Material Expressive only (Sistrum is the sole theme) |
| `3d0d198e` | 2026-10-21 | feat(material): size desktop dialogs and show slider values in pills | N/A: desktop/iOS only |
| `68631cf0` | 2026-10-21 | feat(material): connect the Library tools and chip the month headers | N/A: Material / Material Expressive only (Sistrum is the sole theme) |
| `3fd2ca95` | 2026-10-21 | feat(material): color the player surfaces from the track's artwork | N/A: Material / Material Expressive only (Sistrum is the sole theme) |
| `2e77f63f` | 2026-10-21 | fix(desktop): keep Space for playback next to button groups | N/A: desktop/iOS only |
| `7d936c0f` | 2026-10-21 | docs(theme): list the player artwork theme | N/A: release/CI/docs |
| `6417d804` | 2026-10-21 | feat(material): mark the current track in song lists | N/A: Material / Material Expressive only (Sistrum is the sole theme) |
| `06691967` | 2026-10-21 | feat(material): mark the current track on local album rows | N/A: Material / Material Expressive only (Sistrum is the sole theme) |
| `8b062dc3` | 2026-10-21 | fix(desktop): keep a right-click selection to its menu | N/A: desktop/iOS only |
| `2d2aeea4` | 2026-10-21 | fix(desktop): put delete beside Remove RG in the selection toolbar | N/A: desktop/iOS only |
| `d16efddf` | 2026-10-21 | fix(player): keep the transport inside its row while it resizes | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `9b670696` | 2026-10-21 | fix(material): return Library section headers to the start edge | N/A: Material / Material Expressive only (Sistrum is the sole theme) |
| `007745f1` | 2026-10-21 | feat(material): round Material headings with a fuller Google Sans Flex | N/A: Material / Material Expressive only (Sistrum is the sole theme) |
| `483aa5f5` | 2026-10-21 | feat(material): give desktop album and artist headers the artwork scheme | N/A: desktop/iOS only |
| `6e137fcc` | 2026-10-21 | feat(material): mark the current track in catalog and search lists | N/A: Material / Material Expressive only (Sistrum is the sole theme) |
| `266207b8` | 2026-10-22 | fix(desktop): keep full screen lyrics steady while the panel toggles | N/A: desktop/iOS only |
| `3271bc27` | 2026-10-22 | fix(desktop): open the lyrics panel already on the playing line | N/A: desktop/iOS only |
| `44a5cd71` | 2026-10-22 | fix: keep the album page on top when Go to Album names it | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `c3cb950f` | 2026-10-22 | fix: keep synced lyrics running while the window is unfocused | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `91e00e87` | 2026-10-22 | fix(macos): give the Window menu the system tiling items | N/A: desktop/iOS only |
| `4afe2d7f` | 2026-10-22 | fix(desktop): steady pull to refresh on macOS and add Cmd+R | N/A: desktop/iOS only |
| `11a9b9a4` | 2026-10-22 | chore: remove redundant comments across the codebase | N/A: comment-only cleanup in mostly removed files (no unrelated refactors) |
| `d0dd3792` | 2026-10-22 | feat(macos): add floating mini player with lyrics | N/A: desktop/iOS only |
| `1d87a9fc` | 2026-10-22 | fix(lyrics): keep word highlights moving in inactive windows | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `2f0f0b81` | 2026-10-22 | fix(lyrics): preserve wrapping when lines become active | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `2994a04f` | 2026-10-22 | feat(desktop): show word-timed TTML lyrics in mini player | N/A: desktop/iOS only |
| `6406e0a5` | 2026-10-22 | fix(macos): synchronize mini player window transitions | N/A: desktop/iOS only |
| `eef2a18f` | 2026-10-22 | fix(library): serialize native folder watcher lifecycle | N/A: desktop/iOS only |
| `78fd9ce5` | 2026-10-22 | fix(progress): avoid retained curve listeners on updates | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `060d71a4` | 2026-10-22 | perf(library): remove per-frame scrollbar hide timers | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `e43b8adc` | 2026-10-22 | fix(player): keep transport aligned during parent resizing | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `07a9dd33` | 2026-10-22 | perf(desktop): pause word animation in hidden lyrics panels | N/A: desktop/iOS only |
| `a3767cfc` | 2026-10-22 | perf(player): stop artwork readback in hidden views | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `950bfa80` | 2026-10-22 | chore(settings): use null-aware subtitle element | N/A: style-only change in a widget file we do not have |
| `2cc27c9c` | 2026-10-22 | test(perf): wait for rendered lyrics progression | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `c7f00883` | 2026-10-22 | fix(home): keep feed layout stable during extension startup | N/A: extensions removed |
| `82bda289` | 2026-10-22 | fix(metadata): write M4A tags into FLAC-in-MP4 files | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `0afdacae` | 2026-10-22 | feat(analysis): save the spectrogram as a PNG image | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `45339bf4` | 2026-10-22 | feat(metadata): split the track details into two columns on wide screens | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `b0c60aca` | 2026-10-22 | feat(desktop): mark the desktop version as beta | N/A: desktop/iOS only |
| `9bf4c000` | 2026-10-22 | fix(linux): declare desktop entry spec 1.4 for the release validator | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `1d7f60f5` | 2026-10-22 | chore: update AltStore source to v5.2.5 | N/A: release/CI/docs |
| `b8333537` | 2026-10-22 | fix(desktop): handle missing initial download folders | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `d859d3bf` | 2026-10-22 | fix(android): resolve SAF audio paths when saving lyrics | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `0409a351` | 2026-10-22 | fix(network): flush and verify SMB uploads before publishing | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `7bbdf03e` | 2026-10-22 | feat(desktop): open the mini player on Windows and Linux | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `07f64d9b` | 2026-10-22 | fix(settings): restore 5.2.1 card contrast | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `26acc723` | 2026-10-22 | fix(desktop): add scroll arrows to artist and recent shelves | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `91a7f0b6` | 2026-10-22 | fix(desktop): wrap search and store category filters | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `10b56148` | 2026-10-22 | fix(library): read tagless audio without losing document names | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `4664de14` | 2026-10-22 | feat(player): color the current track row from its artwork | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `bcd81cc8` | 2026-10-22 | fix(library): emphasize Play in collection header actions | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `a1e0e8f0` | 2026-10-22 | fix(home): collapse the empty prompt after installing an extension | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `37466432` | 2026-10-22 | fix(settings): keep final controls clear of floating playback bars | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `226910ee` | 2026-10-22 | fix(library): simplify duplicate review rows and expose load errors | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `8f553c7a` | 2026-10-22 | feat(windows): prepare native ARM64 builds and packages | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `104b8a84` | 2026-10-22 | chore(license): adopt LGPL-3.0-only for Sistrum | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `7649f6b2` | 2026-10-22 | chore: bump version to 5.2.6 (165) | N/A: release/CI/docs |
| `711e6c69` | 2026-10-22 | fix(repo): move the store button under the text on narrow rows | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `7a0d6afb` | 2026-10-22 | fix(notifications): handle Linux launch callbacks and contain queue alerts | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `07bc4c35` | 2026-10-22 | fix(desktop): restore private file access after cache removal | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `2b257c36` | 2026-10-22 | fix(windows): support UNC library paths and network downloads | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `a0acbc1f` | 2026-10-22 | refactor(onboarding): remove the rebrand introduction tour | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `0fe8b7df` | 2026-10-23 | chore(l10n): drop the rebrand tour strings and its seen flag | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `40fff2d7` | 2026-10-23 | fix(library): keep liked local tracks visible during cover fades | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `b80111b4` | 2026-10-23 | test(player): cover mini player metadata refresh and session restore | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `d8903fb2` | 2026-10-23 | fix(windows): install the libmpv license and build on MSVC 14.5x | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `0beadb7c` | 2026-10-23 | fix(windows): use the MSVC coroutine deprecation macro's real name | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `463c2ce9` | 2026-10-23 | fix(android): refresh media controls when track metadata changes | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `f4a14c46` | 2026-10-23 | fix(desktop): keep artist album selection and scroll position | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `9843149d` | 2026-10-23 | fix(automix): start the next song on the outgoing beat | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `fa2f7316` | 2026-10-23 | feat(network): add Subsonic and OpenSubsonic support | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `44a7fad0` | 2026-10-23 | feat(downloads): add custom folder path templates | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `9b747632` | 2026-10-23 | fix(playback): allow MP3 playback with malformed ID3 tags | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `1c2cca66` | 2026-10-23 | fix(library): index songs whose tags fail to parse | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `30a5c82f` | 2026-10-23 | feat(library): list the files a scan could not read | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `6ab91b45` | 2026-10-23 | feat(desktop): add fullscreen and borderless window modes | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `d396fb4c` | 2026-10-23 | fix(conversion): preserve quoted paths in lossy exports | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `e31df404` | 2026-10-23 | feat(library): sort songs and albums by file size | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `56f62efc` | 2026-10-23 | fix(library): keep playlists accessible without local songs | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `f37f7b16` | 2026-10-23 | fix(tags): support ID3-prefixed FLAC metadata writes | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `d8a54db1` | 2026-10-23 | fix(flutter): backport semantics geometry crash fix | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `61b840c6` | 2026-10-23 | fix(home): keep explore artwork square | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `44c9ba92` | 2026-10-23 | fix(automix): verify beat alignment and hold phase through the mix | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `5f2a4dae` | 2026-10-23 | fix(desktop): list full screen and borderless shortcuts | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `8edc3441` | 2026-10-23 | test(library): expect the sort sheet to scroll at its cap | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `499db205` | 2026-10-23 | style(test): format two tests after the repository rename | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `fb4945be` | 2026-10-23 | chore: update AltStore source to v5.2.6 | N/A: release/CI/docs |
| `e8d0a568` | 2026-10-24 | fix(desktop): hide the console window when running FFmpeg on Windows | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `d14a2d72` | 2026-10-24 | fix(windows): bundle the Visual C++ runtime next to sistrum.exe | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `f0b29ea0` | 2026-10-25 | New translations app_en.arb (French) | TRANSLATION: pending translation import batch |
| `c05f688b` | 2026-10-25 | New translations app_en.arb (Spanish) | TRANSLATION: pending translation import batch |
| `4831087b` | 2026-10-25 | New translations app_en.arb (Arabic) | TRANSLATION: pending translation import batch |
| `108c0e60` | 2026-10-25 | New translations app_en.arb (German) | TRANSLATION: pending translation import batch |
| `eb084f25` | 2026-10-25 | New translations app_en.arb (Italian) | TRANSLATION: pending translation import batch |
| `c6f09d9d` | 2026-10-25 | New translations app_en.arb (Japanese) | TRANSLATION: pending translation import batch |
| `0008967a` | 2026-10-25 | New translations app_en.arb (Korean) | TRANSLATION: pending translation import batch |
| `10adb6e8` | 2026-10-25 | New translations app_en.arb (Dutch) | TRANSLATION: pending translation import batch |
| `3f23a061` | 2026-10-25 | New translations app_en.arb (Portuguese) | TRANSLATION: pending translation import batch |
| `64c1c8ae` | 2026-10-25 | New translations app_en.arb (Russian) | TRANSLATION: pending translation import batch |
| `6a30f7ef` | 2026-10-25 | New translations app_en.arb (Turkish) | TRANSLATION: pending translation import batch |
| `0972bbb1` | 2026-10-25 | New translations app_en.arb (Ukrainian) | TRANSLATION: pending translation import batch |
| `2ed2c63c` | 2026-10-25 | New translations app_en.arb (Chinese Simplified) | TRANSLATION: pending translation import batch |
| `327be427` | 2026-10-25 | New translations app_en.arb (Chinese Traditional) | TRANSLATION: pending translation import batch |
| `82a4f5b6` | 2026-10-25 | New translations app_en.arb (Vietnamese) | TRANSLATION: pending translation import batch |
| `d2cd1df4` | 2026-10-25 | New translations app_en.arb (Indonesian) | TRANSLATION: pending translation import batch |
| `8f7da6a2` | 2026-10-25 | New translations app_en.arb (Hindi) | TRANSLATION: pending translation import batch |
| `9a1694a3` | 2026-10-25 | New translations app_en.arb (Indonesian) | TRANSLATION: pending translation import batch |
| `4720f58b` | 2026-10-25 | New translations app_en.arb (French) | TRANSLATION: pending translation import batch |
| `64992769` | 2026-10-25 | New translations app_en.arb (Spanish) | TRANSLATION: pending translation import batch |
| `9a863b57` | 2026-10-25 | New translations app_en.arb (Arabic) | TRANSLATION: pending translation import batch |
| `26627031` | 2026-10-25 | New translations app_en.arb (German) | TRANSLATION: pending translation import batch |
| `d281cd0f` | 2026-10-25 | New translations app_en.arb (Italian) | TRANSLATION: pending translation import batch |
| `a9a6bb10` | 2026-10-25 | New translations app_en.arb (Japanese) | TRANSLATION: pending translation import batch |
| `541aae79` | 2026-10-25 | New translations app_en.arb (Korean) | TRANSLATION: pending translation import batch |
| `9fca2351` | 2026-10-25 | New translations app_en.arb (Dutch) | TRANSLATION: pending translation import batch |
| `ab7a7a77` | 2026-10-25 | New translations app_en.arb (Portuguese) | TRANSLATION: pending translation import batch |
| `7d826867` | 2026-10-25 | New translations app_en.arb (Russian) | TRANSLATION: pending translation import batch |
| `ecabcb01` | 2026-10-25 | New translations app_en.arb (Turkish) | TRANSLATION: pending translation import batch |
| `07d927c2` | 2026-10-25 | New translations app_en.arb (Ukrainian) | TRANSLATION: pending translation import batch |
| `6806146b` | 2026-10-25 | New translations app_en.arb (Chinese Simplified) | TRANSLATION: pending translation import batch |
| `ecc4a4e8` | 2026-10-25 | New translations app_en.arb (Chinese Traditional) | TRANSLATION: pending translation import batch |
| `918d4c4c` | 2026-10-25 | New translations app_en.arb (Vietnamese) | TRANSLATION: pending translation import batch |
| `6ee6c876` | 2026-10-25 | New translations app_en.arb (Indonesian) | TRANSLATION: pending translation import batch |
| `14141255` | 2026-10-25 | New translations app_en.arb (Hindi) | TRANSLATION: pending translation import batch |
| `9b3c9eea` | 2026-10-25 | fix(l10n): validate Crowdin imports and enable Chinese and Vietnamese | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `ca80b76e` | 2026-10-25 | fix(l10n): preserve duplicate warning count placeholders | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
| `c90ec647` | 2026-10-25 | fix(windows): exclude x64 exception runtime from ARM64 bundles | RECORDED: named in reviews/ (ported, already here, or declined with reason) |
