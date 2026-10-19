# Findings

Format and severity: `reviews/PROTOCOL.md`. IDs are never reused. Move entries between
sections instead of deleting them; resolved entries keep the fixing commit SHA.

## Open

### BUG-001 [P2] [confidence: high] [VALIDATED]
- Location: lib/widgets/local_song_file_actions.dart:191 (`splitLocalCue`)
- Scenario: CUE album split where cover embed throws on one FLAC (native error) → loop aborts; earlier tracks already exported, rest never exported, snackbar says "CUE split failed".
- Root cause: `PlatformBridge.editFileMetadata` call has no per-file try/catch (old `_performCueSplit` caught and logged it).
- Impact: partial split reported as failure; user retries and gets duplicates.
- Fix: wrap the embed in try/catch and continue; ~5 lines + test.
- Evidence: old flow at `26f8e71^` wrapped the same call; current loop 189–201 is unguarded inside the outer catch at 209.

### BUG-002 [P2] [confidence: high] [VALIDATED]
- Location: lib/widgets/local_song_file_actions.dart:100 (`splitLocalCue`)
- Scenario: user reopens the menu during a long split and taps Split again → two FFmpeg jobs, two temp audio copies, duplicate files in the destination.
- Root cause: the `_isSplittingCue` re-entrancy guard from the old flow was dropped when moving to a top-level function.
- Impact: doubled CPU/storage, duplicate output files.
- Fix: module-level in-flight set keyed by the backing CUE path; ~6 lines + test.
- Evidence: old `_performCueSplit` returned early on `_isSplittingCue` (`26f8e71^`); no guard in the new function.

### DATA-001 [P2] [confidence: low] [NEEDS VERIFICATION]
- Location: lib/widgets/local_song_file_actions.dart:18 (`isCueSong`) vs :81 (`deleteLocalSong`)
- Scenario: a row with filePath `*.cue` or format `cue+*` but no `#trackNN` suffix would show CUE actions, and Remove from device would call `deleteFile` on the backing sheet/audio.
- Root cause: `isCueSong` is wider than `isCueVirtualPath`, but only the latter protects delete.
- Impact: would break the "deleting a virtual row preserves the backing CUE/audio" rule; deletes a file other tracks depend on.
- Fix: make delete use the same predicate as `isCueSong`, or narrow `isCueSong` to `isCueVirtualPath`; ~2 lines + test.
- Evidence: Rust scanner (`rust_backend/crates/local/src/backend/library.rs:422-427`) always emits `cue+*` rows with a `#trackNN` path, so no producing path was found; verify edited/imported rows and older DB rows.

### UX-001 [P3] [confidence: high] [VALIDATED]
- Location: `lib/l10n/arb/app_en.arb:3108` (`cueSplitConfirmMessage`), all locales
- Scenario: confirm dialog says "Files will be saved to the same directory", then a SAF folder picker opens.
- Root cause: copy not updated when the split moved to a picked destination.
- Impact: misleading prompt; files land outside the expected folder.
- Fix: reword to "You'll choose a destination folder next" in all arb files.
- Evidence: lib/widgets/local_song_file_actions.dart:146 always calls `PlatformBridge.pickSafTree()` after confirm.

### UX-002 [P3] [confidence: medium] [VALIDATED]
- Location: lib/widgets/local_song_file_actions.dart:186-207 (`splitLocalCue`)
- Scenario: split succeeds into a folder outside the scanned library → success snackbar, but no new songs appear.
- Root cause: no library rescan/add after export. Not a regression: the old SAF-source flow also wrote outside the library without rescanning.
- Impact: user must add the folder and rescan manually.
- Fix: after export, trigger an incremental scan when the tree is a library folder, else say where files went; small.
- Evidence: no scan call in the function; old flow (`26f8e71^`) had none either.

### UI-001 [P3] [confidence: high] [VALIDATED]
- Location: `lib/widgets/local_song_menu.dart:127-128`
- Scenario: virtual CUE row → menu shows Edit Metadata (always rejected at :246 with a snackbar) and Copy file path (copies `album.cue#track03`).
- Root cause: both options sit outside the `if (!cue)` block.
- Impact: dead option; clipboard gets a non-file path.
- Fix: hide Edit for `isCueVirtualPath`; copy `stripCueTrackSuffix(path)` or hide copy; ~3 lines + test update.
- Evidence: gating at :129 covers only gain/removeGain/analysis.

### BUG-003 [P3] [confidence: high] [VALIDATED]
- Location: `lib/widgets/local_song_menu.dart:183-190`
- Scenario: Rescan ReplayGain → Cancel → returns true; `LocalAlbumScreen._showTrackMenu` (`local_album_screen.dart:188`) refetches and rebuilds for nothing.
- Root cause: `runBatchReplayGain` returns void, branch returns true unconditionally.
- Impact: wasted refresh only; callers cannot tell cancel from change.
- Fix: return a bool from `runBatchReplayGain`; small.
- Evidence: branch body at :184-190.


### TEST-001 [P3] [confidence: high] [VALIDATED]
- Location: test/local_song_menu_actions_test.dart:124-152 (popover placement loop)
- Scenario: removing the `MornyeContextMenu` height constraint would still pass: 390x844 viewport with anchors at y=100/650 leaves room for the whole menu.
- Root cause: no short-viewport or mid-screen anchor case.
- Impact: popover scroll/clamp behavior (LTR/RTL, above/below) is unprotected.
- Fix: add a 390x420 case with a mid anchor; assert panel height <= free space and last item reachable only by scrolling.
- Evidence: viewport fixed at :75; only two anchor positions.

### TEST-002 [P3] [confidence: high] [VALIDATED]
- Location: test/local_song_menu_actions_test.dart (whole file)
- Scenario: Share, ReplayGain apply/remove, Edit Metadata, Go to album/artist and the CUE split confirm path have no tap tests.
- Root cause: tests cover only Play next, Add to queue, Copy path, Delete and split Cancel.
- Impact: regressions there (incl. BUG-001/BUG-002/BUG-003) pass CI.
- Fix: add tests alongside the fixes for those findings (mocked channel + share stub).
- Evidence: tapped labels at :161, :189, :198, :256, :268.

### TEST-003 [P3] [confidence: medium] [NEEDS VERIFICATION]
- Location: test/local_song_menu_actions_test.dart:199, :257, :269
- Scenario: a single zero-delay `runAsync` then `pumpAndSettle` waits for async lookups before tapping dialog buttons; a longer await chain could make the tap miss.
- Root cause: timing-based waits instead of a condition.
- Impact: possible flakiness (fails loudly, not silently).
- Fix: pump until `find.text(...)` matches, with a bounded loop.
- Evidence: test-auditor reading; not reproduced.

## Resolved

_None yet._

## Rejected

_False positives and intentional behavior, with one-line reason._

- R-001 (`/code-review` #8, share origin from screen context): Android-only app; `sharePositionOrigin` only affects iPad/macOS.
- R-002 (`/code-review` #9, split logic in a widget file): the old screen implementation was deleted, so there is no duplicate; no demonstrated impact.
- R-004 (test-auditor TEST-004, unawaited popover action): no pending future in that test; an open overlay at test end leaks nothing.
- R-005 (test-auditor TEST-005, plain `.cue` delete test): duplicate of DATA-001; its regression test belongs to that fix.
- R-003 (`/code-review` #10, graphify commit title `81577e5` missing "code"): historical pushed commit; fixing needs history rewrite. Future commits follow the AGENTS.md wording.
