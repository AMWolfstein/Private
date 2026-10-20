# Upstream port execution checkpoints

## Completed batch 6 (2026-10-20)

U-210 fits collection covers to short screens. U-217 adds release-triggered upward mini-player opening while keeping horizontal dismissal. U-218 adds bounded normalization pre-amp and Track/Album gain, with one cached tag read and live settings changes. U-303 adds a tappable quality badge and Mornye audio-info sheet with read-only Android route facts, current gain/rate/direct state, local analysis and copied reports.

Source → graph: U-210 `c2f38c86` → `e0f9ba6d` (d28e3f65); U-217 `8a9f6091` → `53b473f0` (37162363); U-218 `0d126507` → `ae93ce55` (9eea6a1a); U-303 `bd8f88a6` → `44cbd9e8` (40f65d3a plus U-209 acbc614f number-pattern reuse). Fixture correction `8b7adfe6` → graph checkpoint (see history); initial imported sheet tests lacked ProviderScope, corrected before final verification.

PASS: analysis clean; Flutter 1670 passed / 3 skipped / zero failures (03:59); Android unit 61 passed / 1 skipped; Rust script NOT RUN (no Rust source changes).
Graph 1735a8c3, source 8b7adfe6: 23,304 unique nodes / 44,944 valid links; synchronized, existing vendor extraction warnings remain.
No APK built; device-only behavior NOT RUN. No dependencies, schema or user-music writes added. Native route support varies by device; actual playback/GPU/route behavior needs device checks. U-303 standalone HiResCheckCard depends on absent services/online wrappers and is excluded; existing AudioAnalysisCard retained. Audio-info EQ reporting is pending U-301 batch 9.
Next: batch 7 (U-308, U-302). User authorized continuing through the remaining PORT_PLAN batches without asking again.

## Completed batch 7 (2026-10-20)

U-308 completes local lyric quote cards, menu/long-press entry points, on-demand document reads and stale-share guards, restyled using retained Mornye controls. Compatible held-word glow honors reduced motion and a bounded fade window, preserving settled/background ticker suspension. U-302 adds optional local music haptics, stable SAF identity and owned decoder jobs, transport synchronization, basic-motor support and bounded sensitivity/strength settings.

Source → graph: U-308 `d83068e6` → `9ae8c833` (78a5e078/2782b1f7); U-302 `df164fb1` → `ba844ef0` (11c6cf99/2455cabc/9acaa760). Follow-ups: artwork guard lint `b02895b0` → `1bb926e3`; Mornye selection fixture `a9433d82` → `6bb22e86`; virtualized-card assertion `de546bd7` → `e0fd4bbe`.

PASS: analysis clean; Flutter 1692 passed / 3 skipped / zero failures (03:55); Android unit 61 passed / 1 skipped; Rust script NOT RUN (no Rust source changes).
Graph e0fd4bbe, source b02895b0: 23,480 unique nodes / 45,224 valid links; synchronized, existing vendor extraction warnings remain.
No APK built; device-only behavior NOT RUN. No dependencies/schema changes or user-music writes. Music haptics defaults off; physical motor sensation/timing and OS share targets NOT RUN. Android VIBRATE permission is the only permission added. Initial quote-limit fixture assumed all rows remained visible; corrected to reveal rows, assert 5/5 and scope preview checks to LyricsShareCard before final verification. New card preserves local artwork policy; no network provider restored.
Next: batch 8 (U-304, U-305, U-307, U-312). User authorized continuing through the remaining PORT_PLAN batches without asking again.

## Completed batch 8 (2026-10-20)

U-304 adds local Rewind highlights and seasonal invitations using recorded listening statistics and Mornye surfaces. U-305 adds pinned Unicode/month section headers and adaptive fast scrolling without changing the dedicated Songs/category layout or bounded paging. U-307 adapts compact launcher-player sizing, preserving existing controls/themes. U-312 bounds restoration checks, virtualizes Settings search, limits logo decoding, avoids redundant static contrast readbacks and scopes pinch updates to the grid.

Source → graph: U-304 `f4fb6794` → `39f9bf4a`; U-305 `6052f9ea` → `ef111d26` (includes U-209 cached locale formatters and U-312 pinned lists); U-307 `2c9c0305` → `e51d221c`; U-312 `c49d7af9` → `c05701ff`. Compatibility fixes `1c589407` → `4f5bc88d`; Rewind header/offline fixture fix `c3d79e0d` → final graph checkpoint (see history).

PASS: analysis clean; Flutter 1739 passed / 3 skipped / zero failures (04:10); Android unit 62 passed / 1 skipped; Rust script NOT RUN (no Rust source changes).
Graph 9020a7aa, source c3d79e0d: 23,813 unique nodes / 45,709 valid links; synchronized, existing vendor extraction warnings remain.
No APK built; device-only behavior NOT RUN. No dependency/schema changes or user-owned music writes. Rewind share targets and launcher resizing on physical devices NOT RUN. Initial analysis mismatches corrected using retained APIs; initial Flutter failures caught an unbounded close control and an upstream remote-source fixture assumption, both corrected before final checks. No runtime speedup measurement. Android widget visual redesign/preview intentionally excluded.
Next: batch 9 (U-301 equalizer only). User authorized continuing through the remaining PORT_PLAN batches without asking again.

