# Calibration

Read only when confidence is low. Real examples from this repo's audit; see `FINDINGS.md`
for full entries.

## Kept

- **DATA-501 [P1]**: the SAF scanner ignores the cursor's `EXTRA_ERROR`, so a provider
  failure looks like an empty folder and that folder's library rows are deleted. It was kept
  because it names the trigger (a provider error), the exact lines
  (`MainActivitySafScan.kt:741-757`), the missing guard and the user-visible loss.
- **UI-101 [P2]**: the mini player hides on pause after one dismissal. The scenario is
  three concrete taps, the root cause is one field that is never reset, and the reviewer
  checked that the state outlives the media item.
- **BUG-301 [P2]**: batch delete of CUE rows fails outside the album screen. The evidence is
  that the CUE branch exists in one caller (`local_album_screen`) and is missing in the
  sibling callers.

## Demoted

- **RUST-001**: the reviewer reported it as unsound `unsafe`. The Opus re-run found that no
  safe caller can reach it, so it became a latent-UB P3. A safety claim needs a caller
  that can trigger it.
- **NEEDS VERIFICATION by arithmetic only** (UX-103, UX-106, font-scale overflow): it stays
  P3 and NEEDS VERIFICATION until someone runs it on a device. The severity is not raised to
  make up for that.

## Rejected

- **R-001**: an iPad/macOS-only parameter in an Android-only app. It is on the auto-reject
  list.
- **R-004**: "unawaited future in a test" where no future was actually pending. The
  reviewer did not trace the trigger.
- **R-005 / R-007 / R-008**: duplicates of open IDs. Merge the new detail into the open
  entry instead of adding a new ID.
- **R-006**: reported as dead code, but `cache_management_page.dart` still uses it. Grep
  every caller in `lib/` before claiming code is dead.
