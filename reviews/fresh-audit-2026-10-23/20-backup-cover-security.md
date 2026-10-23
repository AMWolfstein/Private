# Crafted backup cover publication boundary

## Scope

SEC-02 security-auditor; source d5d5a02 unchanged HEAD5179dfea. P1 reads: lib/providers/library_collections_provider.dart625–682,759–825; services/backup_service.dart80–190,355–385,508–545,555–600,610–755,773–809; rust_backend/crates/mobile/src/native_backup/archive.rs203–280 and legacy.rs1–35,175–232 (whole bodies previously DATA-02-N); screens/settings/backup_restore_page.dart77–140. S1 services/ffmpeg_metadata.dart1–100,ffmpeg_support.dart1–175,ffmpeg_service.dart18–37; AndroidManifest.xml1–24; setup_screen.dart190–225. Fresh03/05/11 read for dedup. Graph restore/cover/archive query completed, truncated navigation only.

## Findings

### SEC-001 [P1] [confidence: high] [VALIDATED — static]

- Location: lib/providers/library_collections_provider.dart:634, _normalizePlaylistCoverFile, reached by restore771–795.
- Scenario: on Android11/12 with requested full-storage grant, restore crafted v3 ZIP with valid JPEG and traversal playlist ID targeting an existing picture; restore overwrites that unrelated JPEG.
- Root cause: untrusted playlist IDs interpolated into source/temp/final filesystem paths without basename/containment checks.
- Impact: accessible JPEG files outside playlist_covers can be overwritten; predictable outside .restore.jpg temporary source is written then deleted too.
- Fix: validate imported IDs, generate safe independent cover filenames, enforce canonical containment on every destination.
- Evidence: ID is './' + twenty '../' + 'storage/emulated/0/Pictures/victim'. Source '.$id.restore.jpg' resolves to /storage/emulated/0/Pictures/victim.restore.jpg; temp '.$id.<timestamp>.jpg' escapes similarly; final '$id.jpg' resolves to victim.jpg. Excess parents clamp at filesystem root. Provider copies/writes source783–789; normalize635–637 writes temp;671 deletes victim then672 renames cover over it. ffmpeg_metadata31–48 passes -y/output unchanged; ffmpeg_support13–15 sends to FFmpegKit.
- Cross-refs: backup_restore_page91–95,133–138; archive245–276; backup_service555–600; Android manifest14–19; setup201–210.
- Guards checked: ZIP validates covers/ entry names, sizes and extension and generates extraction paths, but preserves manifest key and playlist ID. V3 can omit history/settings and use matching data.collections.playlists ID plus data.playlist_covers key pointing to normal covers/a.jpg. Dart transfers these unchanged. Legacy JSON also accepts matching base64 cover map. Confirmation authorizes restore, not unrelated picture overwrite. Mutation queue/image validation/size limits/DB transaction do not constrain path. Android permissions still apply; no permission bypass claimed. Distinct from DATA-006 legitimate-cover rollback.
- Escalation: specialist flagged destructive crafted-file boundary; coordinator independently reread provider585–690/755–825, archive245–302, FFmpeg25–52/support1–21 and setup195–213 under available host model policy. Static path/writer proof confirmed; no alternative model or device proof claimed.

## Verification / limits

No crafted backup/FFmpeg/device execution; no existing user file opened or changed. Static exploit path only; external target requires existing write permission, concretely full-storage grant on API30–32. Native spill JSON source-path confusion is not asserted. Review-only prompt restrictions, no edits. Result FINDINGS, one P1; prioritize separate fix batch.
