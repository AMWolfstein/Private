# Test audit — metadata preservation chunk

Source d5d5a02; definition `.claude/agents/test-auditor.md`; `.claude/skills/audit/SKILL.md`. No old audit comparisons or audio-engine review.

## Scope/read ledger

All bodies of ten files: `test/ffmpeg_opus_metadata_test.dart:1–295`, `ffmpeg_output_promotion_test.dart:1–145`, `id3v23_lyrics_file_test.dart:1–87`, `metadata_persistence_service_test.dart:1–339`, `metadata_editor_controller_test.dart:1–42`, `platform_bridge_metadata_test.dart:1–32`, `replaygain_service_test.dart:1–271`, plus `lib/services/ffmpeg_metadata.dart:1–458`, `metadata_persistence_service.dart:1–263`, `id3v23_lyrics.dart:1–244`.

## Findings/acceptance requirements

No independent test-logic defect. Concrete missing failure coverage is attached to DATA-001 rather than duplicated: metadata_persistence_service_test316–321 and ReplayGain test56–59 mock write-back as a boolean without destination bytes. Their cleanup assertions can pass when actual Android publication truncates the original and deletes the recovery copy. Required disposable provider fixture: truncate, write a prefix, throw; assert original or retained recovery remains. Include source-open failure.

Existing positive evidence: local promotion tests assert original preservation under real filesystem failures; ID3 tests hash audio tails; save-resource tests use completers for disposal ownership; Opus tests inspect tags/artwork/audio hashes. Four Opus round-trip scenarios explicitly skip at187–190 if ffmpeg/ffprobe missing; tool availability alone is not an executed pass.

Graphify broad query narrowed to path-qualified metadata_persistence_service_test (18 connections). Source review PASS within scope. Flutter/provider test execution NOT RUN; full remaining test inventory not yet reviewed. Coordinator independently ran14 Rust tag unit tests successfully and reproduced DATA-002/003; see VERIFICATION.md.
