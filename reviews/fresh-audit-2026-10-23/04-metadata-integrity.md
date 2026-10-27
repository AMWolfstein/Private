# Metadata/file-write integrity audit

> Identity normalization (T16, 2026-10-28): historical names, paths and command strings below were mechanically renamed. Original evidence used the former terms; no listed checks were rerun by this rename. Encoded upstream/download identifiers retain their actual destinations.

Application source `d5d5a02ecdad86dca50a4448cf7810b7eec43ad9`. Definitions: `.claude/agents/data-integrity-auditor.md` and `.claude/agents/rust-safety-auditor.md`; `.claude/skills/audit/SKILL.md`. Independent current-source review. Playback engine excluded; metadata/tag/lyrics/ReplayGain file editing retained.

## Findings

### DATA-001 [P1] [confidence: high] [VALIDATED — static caller trace]

- Location: `android/app/src/main/kotlin/com/amwolfstein/sistrum/MainActivitySafIo.kt:377` (`writeUriFromPath`).
- Scenario: metadata/ReplayGain edit of a SAF song opens the destination with `wt`; storage/provider failure interrupts copying. The original is now empty/partial and the complete staging copy is deleted.
- Root cause: destructive direct publication without rollback/recovery, followed by unconditional temporary-input cleanup.
- Impact: loss/corruption of user music after a failed ordinary edit.
- Fix: validate/open input before destination; use provider-supported staged replacement or verified recovery/rollback. Retain the last complete copy when publication fails and report its recovery location.
- Evidence/cross-refs: `MainActivity.kt:990–1011` copies/edits/writes/deletes on native path; `1039–1052` deletes fallback input in `finally`; `metadata_persistence_service.dart:147–161` and `replaygain_service.dart:220–238` also clean failed staging.
- Guards checked: source existence at SafIo376 does not prevent failed open/partial write; Rust local atomic publication protects only the local staging file. Coordinator independently re-read SafIo355–400, MainActivity1024–1068 and Dart callers.
- Verification: static failure path validated by two specialists and coordinator; actual Android provider failure injection NOT RUN. High-impact review escalated to coordinator under host SOL-only policy; no alternate model was used. Required regression: disposable provider truncates, writes N bytes, then throws; both native/fallback paths preserve original or recovery bytes.

### DATA-002 [P2] [confidence: high] [VALIDATED — reproduced]

- Location: `rust_backend/crates/core/src/tags/write/id3.rs:253` (`read_frames`).
- Scenario: edit only title in MP3 with valid ID3v2.4 six-byte extended header followed by artist/custom frames. Save succeeds and untouched frames disappear.
- Root cause: v2.4 size includes its size field, but parser prefers `length + 4`, skipping the first frame ID.
- Impact: artist/custom metadata, potentially lyrics/artwork, silently lost.
- Fix: version-specific extended-header size semantics and strict malformed-frame rejection.
- Evidence/cross-refs: id3.rs212–369 supplies retained frames to edit_header45/149–163; write.rs76–90; local/backend/tags.rs95–103 reports native success.
- Guards checked: overall/frame bounds do not repair offset; incomplete parsing still publishes success. Coordinator inspected id3.rs215–280.
- Verification: actual current core API returned `Ok(())`, original artist absent, audio tail retained; checked-in harness and exact commands in VERIFICATION.md.

### DATA-003 [P2] [confidence: high] [VALIDATED — reproduced]

- Location: `rust_backend/crates/core/src/tags/write.rs:380` (`flac_header`).
- Scenario: choose nonempty corrupt replacement image >16,000,000 bytes, leave optional resize unset, save existing FLAC artwork. Save succeeds without the existing or replacement artwork.
- Root cause: remove old PICTURE blocks before `picture()` can return `Ok(None)` for rejected replacement.
- Impact: silent loss of existing cover.
- Fix: validate/build new picture before discarding old pictures; fail safely or preserve old cover when encoding fails.
- Evidence/cross-refs: write.rs735–742/772–774; sheet270–294 accepts selected bytes and resize defaults null59; metadata_cover_resources83–104/129–144 checks nonempty but uses probe:false; persistence80–100 forwards unchanged cover.
- Guards checked: 64MiB input bound permits trigger; existing oversized-picture helper test does not test full rewrite preservation. Coordinator directly read flac_header292–393 and picture730–792.
- Verification: actual core API returned `Ok(())`, original cover absent; harness in reproductions/tag_writer.rs.

### DATA-004 [P2] [confidence: high] [VALIDATED — static]

- Location: `rust_backend/crates/core/src/tags/write/riff.rs:88` and `152`.
- Scenario: edit title on WAV/AIFF with unrelated ID3 TXXX/PRIV frame; custom frame disappears.
- Root cause: ordinary edit deletes existing ID3 chunks and reconstructs from limited AudioMetadata fields.
- Impact: unrelated embedded metadata silently lost.
- Fix: edit original ID3 frames, constructing fresh tag only when none exists.
- Evidence/cross-refs: riff.rs88–92 deletes chunk;152 fresh tag; id3.rs21–34 starts empty; write.rs576–626 enumerates fields; local/backend/tags.rs81–93 treats supported native writer as success.
- Guards checked: ReplayGain-removal-only branch riff48–78 preserves frames but ordinary title edits bypass it. Artwork extraction does not preserve custom frames. Coordinator independently read riff1–180.
- Verification: static trace; custom-frame/audio round-trip fixture still required.

### DATA-005 [P2] [confidence: high] [VALIDATED — static]

- Location: `rust_backend/crates/core/src/tags/write/ape.rs:81`.
- Scenario: clear date on APE/WavPack/Musepack with existing `Year=2024`; save succeeds and year returns on refresh.
- Root cause: empty date removes DATE, but YEAR survives because no replacement Year item is added.
- Impact: release date cannot be cleared on supported formats.
- Fix: remove both DATE and YEAR aliases for every date edit, including empty values.
- Evidence/cross-refs: ape62 maps date to Year;78–94 removes DATE and skips empty replacement;139–145 retains YEAR; comments136–142 parses it and library227–228 falls back to year.
- Guards checked: nonempty edit adds Year and triggers alias removal; specifically absent on clear. Coordinator read ape20–155 and reader alias references.
- Verification: static trace; persisted alias-clearing fixture still required.

## Read ledger

Principal Dart chunk, complete bodies: `lib/services/ffmpeg_cue.dart:1–95`, `ffmpeg_metadata.dart:1–458`, `ffmpeg_models.dart:1–69`, `ffmpeg_probe.dart:1–36`, `ffmpeg_replaygain.dart:1–179`, `ffmpeg_service.dart:1–126`, `ffmpeg_support.dart:1–187`, `metadata_cover_resources.dart:1–157`, `metadata_persistence_service.dart:1–263`, `id3v23_lyrics.dart:1–244`, `replaygain_service.dart:1–242`, `lib/controllers/metadata_editor_controller.dart:1–102`.

Principal Rust writer chunk: `core/src/tags/write.rs:1–1197`; `write/ape.rs:1–210`, `id3.rs:1–370`, `mp4.rs:1–612`, `ogg.rs:1–225`, `riff.rs:1–187`; `local/src/backend/tags.rs:1–270` (Rust paths under rust_backend/crates).

SAF chunk: MainActivitySafIo.kt1–327/332–436; MainActivity.kt900–1055; NativeMediaWorkspace.kt1–48. Supplemental caller chunk: local_song_file_actions.dart100–230; track_metadata_edit_sheet.dart1–75/225–357; PlatformBridge482–517; SelectedCoreBackend286–300; local/files547–620; tags.rs1–45/180–215; containers312–415/476–510; comments124–160; library216–233.

## Evidence and limits

Graphify metadata queries narrowed to `MetadataPersistenceService` (32 nodes/31 edges). Broad writer query truncated; direct reads supplied evidence. CUE `-y` overwrite candidate rejected: real caller stages into a fresh per-invocation directory. Sheet save reentry guarded at315–317; artwork resource ownership and local promote rollback present. No additional Dart-only finding.

14 Rust tag unit tests PASS; two direct defects reproduced. Flutter tests BLOCKED by unavailable Flutter toolchain at time checked. SAF provider execution, RIFF/APE fixtures and full format corpus NOT RUN. No application fixes. Prior trust-boundary checkpoint `f862a6e` pushed successfully.
