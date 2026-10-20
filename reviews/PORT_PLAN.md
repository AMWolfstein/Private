# Port plan for Codex

Planned 2026-10-20 by Claude Code; implementation is done by Codex. Specs per item are in
`reviews/UPSTREAM.md` (U-IDs) and `reviews/FINDINGS.md` (MORN/HOME/PLAY/DEAD IDs). Obey
`AGENTS.md` throughout.

## Setup (once)

```sh
git clone --filter=blob:none https://github.com/mornyeapp/Mornye.git ../mornye-upstream
git -C ../mornye-upstream log -1 --oneline   # expect e0563ffa or newer
```

The clone is read-only reference data: never build it or run its scripts. Read commits with
`git -C ../mornye-upstream show <sha>` and `show <sha>:<path>`. Mornye is SpotiFLAC-Mobile
renamed (same history), so every SHA in `UPSTREAM.md` exists there. Histories are not shared
with this repo: port by hand. Use `git apply` only when
`git -C ../mornye-upstream format-patch -1 --stdout <sha> | git apply --check` passes.

## Rules for every port

- **No renaming or branding.** Mornye renamed `package:spotiflac_android` to `package:mornye`,
  the app to Mornye and the native backend crates. Read `package:mornye/` as
  `package:spotiflac_android/`; keep this repo's names, ids, `com.zarz.spotiflac` paths,
  strings and assets. Skip the commits listed under "Skip all renaming/branding".
- Port only what fits `AGENTS.md`: drop download, extension, provider, network/NAS/SMB/WebDAV,
  online lyrics, remote artwork, iOS, Discord, crash-notice and Material-only parts. The lyric
  spring scroll (`91add520`) is wanted; Material Expressive spring motion is not.
- New UI is Mornye-styled: existing Mornye widgets (`HeaderCircleButton`, `SettingsGroup`,
  `SettingsItem`, `MornyeSettingsTheme`, `showAppBottomSheet`), Cupertino icons, light/dark.
- Never replace the audio engine; DSP sits on the existing player.
- When a commit depends on an earlier upstream refactor, port the minimum pieces, not the
  refactor.
- Before editing, use graphify for links and blast radius: `graphify query "<question>"`,
  `graphify explain "<Symbol>"`, `graphify path "<A>" "<B>"`.
- l10n: add new keys to `lib/l10n/arb/app_en.arb` (other locales fall back to English).
- Code generation is allowed when needed (`dart run build_runner build
  --delete-conflicting-outputs`, `flutter gen-l10n`, uniffi bindings through the repo scripts).
- Do not build APKs.

## Commits

Per port (one upstream commit or one logical piece):
1. Code commit, explicit paths only (never `git add -A`; no `graphify-out/`, no
   `LOCAL_OFFLINE_MIGRATION_PLAN.md`): `feat(port)|fix(port)|perf(port): <what> (upstream <sha>)`.
2. `graphify update .`, then commit only tracked `graphify-out/` files:
   `chore(graphify): refresh code graph after <ID>`.

No tests between ports. Testing happens once at the end of each batch.

## End of every batch

1. `flutter analyze`: `No issues found!`
2. Full `flutter test`. Accepted failures only: the known-flaky
   `test/library_browse_sqlite_paging_test.dart` and the `file_stat_boundary_test`
   permission case when running as root. Port upstream tests that cover ported behaviour.
3. Rust changed: `bash scripts/check_rust_backend.sh` (fmt, clippy `-D warnings`, tests).
4. Kotlin changed: run Kotlin unit tests only if a Gradle unit-test task works without
   building an APK; otherwise note it.
5. Fix failures in `fix(port)` commits, each followed by a graphify commit.
6. Docs commit `docs: record upstream port batch <n>`: mark each ID in `UPSTREAM.md`
   (`ported in <sha>` / `partial: <why>`) or `FINDINGS.md` (move to Resolved with the SHA), add
   a `## Progress` entry in `LOCAL_OFFLINE_MIGRATION_PLAN.md`, and one `AGENTS.md` line only for
   a lasting product rule.
7. `git push -u origin ccr-2fb644cd-nmesyt`, then fetch and confirm HEAD equals the remote.

## State at hand-over

- Initial hand-over: batch 1 (U-001 `5393d1d`, U-101 `a5bc4a8`, U-102 `051ff44`, U-103
  `940fd79`; tested). Batch 2 part: U-104 `913faaa`, U-201 `e8cff13`, now tested by batch 1b (see completed checkpoint below).
- `reviews/wip/U-202-flac-precision.patch` holds unfinished, untested work for `3dc2d690`
  (Kotlin/C++ FLAC PCM source, 18 files; it includes a `pubspec.yaml.rej`, i.e. one upstream
  hunk did not apply). It applies cleanly to `96a1e43` (`git apply`). `3dc2d690` is unchanged in
  Mornye. In batch 2, review it against `3dc2d690`, then reuse or drop it; never commit the
  `.rej` file, and delete `reviews/wip/` in that batch's docs commit.
- Dependencies were compared with Mornye `e0563ffa`: every shared pub package, Cargo crate,
  the Flutter pin (`.fvmrc` 3.47.7), NDK `30.0.16248370` and Gradle plugin versions are
  identical. Mornye's extra dependencies are online/iOS/Discord only (`cached_network_image`,
  `connectivity_plus`, `dart_smb2`, `flutter_secure_storage`, `http`, `url_launcher`,
  `video_player`, `receive_sharing_intent`, `material_symbols_icons`, `dynamic_color`,
  tokio/hyper/rustls/rquickjs crates): do not add them.

## Completed batch 1b (2026-10-20)

- `f10f45f6`: U-103b spring scroll (`91add520`), fast scrubbing and reduced-motion behavior retained.
- `81869c48`: U-103b lyric-only performance (`7600c169`): indexed active voices, deferred/bounded row measurement and prefix geometry, lifecycle/TickerMode subscription suspension, completed-word clock settling. The current single-file widget is retained. U-308 prerequisites from `78a5e078` (overlap focus, display ends and backing drop-in) included; sharing/glow/provider/Material-only code omitted.
- U-104 `913faaa` and U-201 `e8cff13` validated; `f34ead84` fixes the U-201 nullable-element lint. Graph checkpoints `dd04bf17`, `1bc2b9e3`, `ec2f8bf3` (no topology change) and `11456f4f` (extraction hash).
- Generated ignored l10n files refreshed after the branch switch. Final `flutter analyze`: No issues found; full `flutter test`: **1,629 passed, 3 skipped, no failures**. Android `:app:testDebugUnitTest --offline`: **59 passed, 1 skipped**, including 2/2 LibraryScanExitInfo tests. The skipped class is NativeDataJobsTest. No APK packaging task ran. Rust check script not required/run (no Rust source changed in this batch); Gradle rebuilt native dependencies for unit checks.
- Graph JSON validated: 23,003 unique nodes and 44,612 valid links. Existing vendored C/preprocessor extraction warnings remain; no new application extraction errors. Tests ran at batch end; no tests between the two ports. Source/graph/docs commits remain separate.
- **Next: batch 2 only (U-201b, U-202)**. WIP FLAC patch remains untouched in `reviews/wip/`; review its native/precision changes before applying and omit its `.rej` entry. Determine whether scan-memory fixes cover KT-202. No APK.

## Batches

| # | Items | Notes |
|---|---|---|
| 1b DONE | U-103b | `7600c169` lyrics parts only (`player_lyrics.dart`, `player_lyrics_word_sweep.dart`, `utils/lyrics_timeline.dart`, `lyrics_timeline_test`, `player_lyrics_repaint_test`, lyrics bits of `now_playing_lyrics_transition_test`) + `91add520`. Upstream split `player_lyrics.dart` in `77c8639d`; port behaviour, not the split. If it needs `78a5e078` timed-vocal code (`_focusFor`, `lyricsWithDisplayEnds`, `LyricBackingTransition`), port those pieces here and mark U-308 partly done. Also fix any failures from U-104/U-201. |
| 2 | U-201b, U-202 | U-201b: local parts of `e58217c8` (`local_library_provider*.dart`), plus `931b1091` `LibraryScanExitInfo` only if U-201 needs it. U-202: see the stash above. Say whether U-201 fixes open finding KT-202. |
| 3 | U-203, U-212, U-213, U-204 | U-212 `9dc86e13` without `crates/extensions`. |
| 4 | U-205, U-216, U-206, U-207 | |
| 5 | U-214, U-215, U-208, U-209 | U-215 touches `third_party/audio_service`; record the patch in its patches note. U-209: skip download/iOS hunks. |
| 6 | U-210, U-303, U-217, U-218 | U-210: only the `album_detail_header` part of `d28e3f65`. U-303 brings `audio_info_sheet.dart` (not in this repo). U-217: mini-player dismissal must keep working (UI-101). |
| 7 | U-308, U-302 | U-308: timed-vocal parts (if not done in 1b) and the lyric share screen restyled for Mornye. U-302: `11c6cf99`, `2455cabc`, `9acaa760`. |
| 8 | U-304, U-305, U-307, U-312 | U-312: Mornye/library parts of `7600c169` (skip Material files); `pinned_section_sliver_list` goes with U-305. |
| 9 | U-301 | Equalizer, alone: `ecf594aa` + `68c739df`, Kotlin/native DSP on the existing player. |
| 10 | MORN-001..005, MORN-017 | `FIX_PLAN.md` M1+M2. |
| 11 | MORN-006..012 | M3+M4. |
| 12 | MORN-013..016 | M5+M6; MORN-013 uses the tonal style (owner decision). |
| 13 | HOME-001..008 | M7-M9 + HOME-007 cleanup. |
| 14 | PLAY-001..004, U-311 | M10+M11 + the upstream full-screen look for the Immersive view (`UPSTREAM.md` U-311). |
| 15 | Dependencies | Re-run the comparison above against the then-current Mornye `main` and against anything the ports added. Apply version bumps only for packages/crates this repo uses. Expected: no change. |
| 16 | Dead code, one patch | `FIX_PLAN.md` Tier 3 (rows 22-27, 25a-d) and HOME-007 leftovers if still present. First re-run the dead-code checks with graphify and grep, because ports may now use code that was dead (e.g. widgets, l10n keys). Keep `NativeReplayGainPolicy` (owner decision) and `MANAGE_EXTERNAL_STORAGE`. Follow the `AGENTS.md` feature-removal workflow; delete the l10n keys last and re-scan. |

Batches 10-14 come after the ports because the ports touch the same screens.

## Owner decisions that apply

- Tag separators under Local Library settings (done).
- Optional ports chosen: U-301, U-302, U-303, U-304, U-305, U-307, U-308 (duets and share
  cards). Not ported: U-306 crash reports on Home, U-309 Home greeting, the On Repeat shelf.
- MORN-013 tonal style. U-311: Immersive keeps this repo's Player view setting and takes only
  upstream's Mornye full-screen look.
- About credits/links and the Search Recent list stay removed; keep `MANAGE_EXTERNAL_STORAGE`
  and `NativeReplayGainPolicy`.
