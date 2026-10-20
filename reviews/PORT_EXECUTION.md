# Upstream port execution checkpoints

## Completed batch 6 (2026-10-20)

U-210 fits collection covers to short screens. U-217 adds release-triggered upward mini-player opening while keeping horizontal dismissal. U-218 adds bounded normalization pre-amp and Track/Album gain, with one cached tag read and live settings changes. U-303 adds a tappable quality badge and Mornye audio-info sheet with read-only Android route facts, current gain/rate/direct state, local analysis and copied reports.

Source → graph: U-210 `c2f38c86` → `e0f9ba6d` (d28e3f65); U-217 `8a9f6091` → `53b473f0` (37162363); U-218 `0d126507` → `ae93ce55` (9eea6a1a); U-303 `bd8f88a6` → `44cbd9e8` (40f65d3a plus U-209 acbc614f number-pattern reuse). Fixture correction `8b7adfe6` → graph checkpoint (see history); initial imported sheet tests lacked ProviderScope, corrected before final verification.

PASS: analysis clean; Flutter 1670 passed / 3 skipped / zero failures (03:59); Android unit 61 passed / 1 skipped; Rust script NOT RUN (no Rust source changes).
Graph 1735a8c3, source 8b7adfe6: 23,304 unique nodes / 44,944 valid links; synchronized, existing vendor extraction warnings remain.
No APK built; device-only behavior NOT RUN. No dependencies, schema or user-music writes added. Native route support varies by device; actual playback/GPU/route behavior needs device checks. U-303 standalone HiResCheckCard depends on absent services/online wrappers and is excluded; existing AudioAnalysisCard retained. Audio-info EQ reporting is pending U-301 batch 9.
Next: batch 7 (U-308, U-302). User authorized continuing through the remaining PORT_PLAN batches without asking again.

