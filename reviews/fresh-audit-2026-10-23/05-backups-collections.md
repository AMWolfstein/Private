# Backup/collection persistence audit

Source `d5d5a02ecdad86dca50a4448cf7810b7eec43ad9`. Definitions: `.claude/agents/data-integrity-auditor.md`, `.claude/agents/api-compat-auditor.md`; `.claude/skills/audit/SKILL.md`. Current-source review only, old findings not imported, audio engine excluded.

### DATA-006 [P2] [confidence: high] [VALIDATED — static]

- Location: `lib/providers/library_collections_provider.dart:670–672`, `_normalizePlaylistCoverFile`.
- Scenario: restore different artwork for an existing playlist ID, then collection database import fails. Old database rows survive but their cover has already changed. A rename failure after destination deletion can instead lose both old cover and prepared temporary image.
- Root cause: deterministic `$playlistId.jpg` publication precedes database commit; delete-before-rename and unconditional cleanup offer no recovery.
- Impact: failed restore or cover update loses/changes previous playlist artwork.
- Fix: prepare versioned covers, commit new paths with collection rows, then retire old covers. Preserve recoverable files on failed publication.
- Evidence/cross-refs: provider634 deterministic path;670–678 delete/publish/cleanup;794–797 normalizes before820 database replacement. setPlaylistCover601–624 uses same helper; library_collections_database942–968 transaction protects rows only.
- Guards checked: mutation serialization, resized-file validation and DB transaction do not roll back filesystem publication. Coordinator independently read provider585–690/759–828.
- Verification: static source trace; injected database/rename failure and byte-preservation tests NOT RUN.

### DATA-007 [P2] [confidence: high] [VALIDATED — static]

- Location: `rust_backend/crates/mobile/src/native_backup/archive.rs:211`, contrasted with exporter94.
- Scenario: a legitimate large playlist/collection export produces metadata.json >8MiB; export succeeds, but restoring that same backup fails as oversized.
- Root cause: export permits unrestricted metadata size while import caps it at `8 << 20`.
- Impact: apparently successful backups of larger libraries cannot be restored.
- Fix: make format/export/import limits agree; preferably stream large collection data separately or validate before declaring export success. Add a just-over-boundary self-export/import fixture.
- Evidence/cross-refs: archive14 defines bound;70–104 copies export entries with u64::MAX and reports published;203–217 rejects metadata exceeding limit. BackupService20–73 streams collections without a size gate;249–273 builds/writes metadata;767–771 delegates without bound; collection provider720–723 hydrates all tracks.
- Guards checked: photo/cover bounds protect images, not collection JSON. Archive entry naming and individual file validation do not impose metadata parity. Coordinator read archive70–112/190–232 and Dart writer20–82/245–275/755–780.
- Verification: static mismatch confirmed independently; large legitimate round-trip fixture NOT RUN. Do not remove import bounds without preserving resource limits.

## Exact read ledger

Data-integrity principal chunk (all bodies): `lib/services/backup_service.dart:1–809`, `collection_restore_codec.dart:1–105`, `collection_track_batch.dart:1–267`, `library_collections_database.dart:1–1125`, `library_collections_hydration.dart:1–617`, `m3u_playlist_service.dart:1–195`, `history_database.dart:1–595`, `history_maintenance.dart:1–69`, `app_state_database.dart:1–226` (persistence schemas), `user_profile_store.dart:1–127`.

Supplemental caller chunk: `lib/screens/settings/backup_restore_page.dart:1–352`, `lib/providers/library_collections_provider.dart:1–130,350–410,565–824`, `lib/models/library_collections.dart:1–100,130–225`, `lib/services/csv_import_service.dart:1–177`, `lib/services/sqlite_native_snapshot.dart:1–138`.

Native reviewer supplied exporter/importer size-mismatch lead but did not return a complete native read ledger because its turn failed. Coordinator's independently read native ranges are listed under DATA-007; other native backup/schema bodies remain unverified and MUST NOT count as fully reviewed.

## Verification and limitations

Graphify query `BackupService LibraryCollectionsDatabase restore` completed with31 nodes/39 edges; direct source establishes findings. No runtime fixtures, Android provider execution or legacy/current round trips executed. M3U helper production callsites not found; no speculative import-matching bug reported. Native archive/collection/playlist whole-body coverage remains partial, as does full provider/model-body coverage.

Prior metadata checkpoint `4538b74` pushed successfully to origin/ccr-2fb644cd-nmesyt. No app changes.
