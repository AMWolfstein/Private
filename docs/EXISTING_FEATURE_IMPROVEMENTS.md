# Existing-feature improvement implementation

Owner-authorized implementation on 2026-11-02. This follows the reviewed backlog
in `docs/PLAYBACK_COMPARISON.md` and the Mornye theme comparison. Upstream reference:
`7db0fc76f6cfeaef903327ebc73e13d9bdc3d936`. It develops the current local/offline
Android app and its existing engines. No playback-engine migration is involved.

## Completed scope

| Area / backlog item | Implementation |
|---|---|
| Autoplay: candidate diversity | Read eight small pages distributed across the library plus a smaller seed-artist page, retaining bounded reads and local-source checks. Small libraries use one bounded page. |
| Autoplay: session-aware variety | Rank genres from the latest session songs, prefer artist spacing when alternatives fit, discourage repeated albums and fall back for small libraries. Explicitly queued tracks remain outside the recommendation selection. Random exploration stays separate from score parts; learned weights apply to actual score contributions. |
| Autoplay: co-listening taste | Adapt upstream local skip-gram song/artist vectors. Retain at most 5,000 metadata-keyed plays, split sessions after 30 minutes, train on a worker every 25 new plays and wait for 50 positive plays before applying the signal. Unknown songs are neutral. Runtime owns opted-in feedback, persistence and disposal. Reset recommendation learning clears this model/log along with preferences and score weights; generation guards reject retired training, and storage-clear failures are visible/retryable. |
| I-1: statistics covers | Preserve a known durable cover when a later play lacks one; summaries recover the latest covered day. Rewind's first song and most-replayed song can use the summary's cover. |
| I-2: durable cover references | Reject process-bound loopback URLs and temporary cover files when reading/writing statistics. No remote artwork loader is added. |
| I-3: collaborative artists | Monthly leaders, loyalty and discoveries split credits with the existing Tag separators/Keep together rules. Canonical participant labels merge case variations, distinct-day loyalty counts a day once, and cover labels match the summary's artist identities. Original track credits remain intact. |
| S-1: stable rescan covers | Extraction keeps its fresh generation directory. Only after indexing succeeds are complete thumbnails atomically published under stable basenames, then DB references updated. A publication failure retains valid staged references. Cancellation after indexing refreshes the committed index and clears scan state. Decoded artwork is invalidated after successful publication. |
| S-2: prune protection | Add cover references from existing local collections, the saved playback session and statistics. Read long JSON in bounded chunks. Hold the copied-reference stores' writer barriers in stable path order through pruning, and include their references in the detached private projection. A failed reference read prevents pruning. Existing library writer/reference-handoff guards and minimum-age protection remain. |
| L-1: saved crash/ANR diagnostics | Persist the latest confirmed Java/native crash or ANR independently of the live log buffer. Android 11+ exit-history recovery runs off Application.onCreate; Java uncaught reports remain available independently. Exclude normal shutdown, force-stop and resource reclamation from crash notices. Display/copy the saved report from Logs after restart. Initialization failure does not prevent app startup. |
| L-2: diagnostic context | Attach bounded/redacted Dart error, stack and recent log context, and available Android/native traces. Native trace input and displayed text are bounded; waiting for recovery has a deadline. Do not fabricate missing traces or resolved native symbols. The platform channel works for attached and headless engines. |
| T-1: Settings alignment | Groups and section labels share responsive horizontal insets, including narrower sheets and wide layouts. Font sizes and weights remain unchanged. |
| T-2: supporting text colour | Leading/subtitle text in the shared track row inherits its supporting colour unless the caller supplies one. Material-only current-row styling is excluded. |
| T-3: theme reuse | Derive artwork-chrome variants from a cached base theme, retaining bounded caching, custom/system font precedence, bundled Arabic fallback and glass preferences. No measured performance gain is claimed. |

The separately completed Arabic-font batch is recorded in `docs/ARABIC_FONT.md`.
The removed statistics recording toggle remains absent. Insights stays in its own
tab, Song analysis stays under Local Library, and existing always-on logging and
Full logcat/filter/selection/share controls remain.

## Important implementation boundaries

Stable cover publication is a post-index operation: the scan's extraction stage
never overwrites the prior published index's covers. If publication is interrupted,
rows continue naming a complete staged or stable file. Legacy references into old
`full_scan_*` directories remain protected by the copied-reference projection;
they are not silently rewritten. A changed source's versioned cover key can still
change its basename. No arbitrary cover-file migration or history deletion occurs.

Copied-reference discovery is composed in
`lib/services/storage/library_cover_references.dart`; library pruning accepts plain
reference columns instead of directly depending on playback/statistics stores.
The native maintenance job reads a private detached projection, not live databases.
No removed download/history tables are recreated.

The co-listening model complements the existing preference learner and acoustic
signal; it is not acoustic analysis and its 50-play threshold is distinct from the
score-weight ranker's 40-outcome evaluation threshold. Logs and model data remain
local. Full recommendation quality, perceptual audio continuity and physical-device
CPU/battery behavior were not measured by host tests.

Crash reporting retains local reports only; it adds no network endpoint or remote
submission. An unhandled Dart error is saved as context and does not by itself
prove a process crash. AppCrashReporter and native tombstone parsing are adapted
from upstream; attribution and complete LGPL terms are in
`assets/licenses/diagnostics.txt`. Autoplay adaptations retain notices and the
existing complete in-app license. No Rust/C++ algorithm source changed.

## Verification

Source checkpoint: `0a2e9dc2`. `flutter analyze`: **No issues found**.
Full Flutter suite: **2,440 passed / 3 skipped / zero failures** (5m47s).
Android app JVM: **105 passed / 1 skipped / zero failures**; final Gradle
check completed in 22s. Native compilation/device execution are distinct:
no emulator/physical-phone test, instrumentation run or APK packaging occurred.
No Rust/C++ source changed, so no new Rust algorithm test result is claimed.

An intermediate full-suite run was intentionally stopped during final review to
correct post-index scan cancellation. Its interrupted shutdown output is not a
successful suite result. The cancellation regression was added and the complete
suite rerun successfully. Earlier focused failures reflected outdated ranking
expectations and an in-memory database sharing a test connection; the fixtures
and behavior assertions were corrected before the passing verification above.
Graph checkpoint: `b839b5c8`, built from `0a2e9dc2`: **29,353 unique nodes /
56,003 valid links / zero dangling endpoints**. Existing vendored/generated
extraction limitations remain.
Focused coverage includes 164 Autoplay/statistics/cover/report tests, 28 scan
scheduling/publication tests including post-index cancellation, and a final
31-test statistics/Rewind pass after participant-label canonicalization.
Android app host tests cover exit classification, trace decoding and existing
native bridges. Instrumentation/device execution is not claimed.
