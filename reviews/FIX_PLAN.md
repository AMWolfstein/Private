# Fix plan

These batches are proposals and have not been approved. Each one follows `PROTOCOL.md` Fix
batches (with `review-fixer`) and the `AGENTS.md` code → graphify → docs commits. Do them in
order. Pick up any NEEDS VERIFICATION item in a batch only after confirming it in that batch.

## Tier 1: data on disk, library and backups

| # | Findings | What it fixes |
|---|---|---|
| 1 | DATA-501 | A SAF provider error wipes that folder's library rows (P1). |
| 2 | DATA-001, BUG-301, TEST-301 | CUE virtual-row delete stays safe, and works outside the album screen. Adds the missing regression test. |
| 3 | BUG-001, BUG-002 (+TEST-002) | CUE split: a per-file embed failure no longer aborts the split, and running Split twice is guarded. |
| 4 | KT-201, KT-202, KT-203 | SAF incremental and resumed scans: changed CUE sheets, removed files and resume state. |
| 5 | DATA-302, DATA-303 | FFmpeg tag embedding for MP3/M4A loses or corrupts fields. |
| 6 | DATA-306, DATA-301 | SAF write-back after edits, and the metadata editor flow. |
| 7 | RUST-102, RUST-402 (+BUG-104) | The same truncating `break` pattern in ID3 frame reading and writing. |
| 8 | DATA-502, CONC-102, CONC-101 | 32-bit library and cover IDs collide, and CUE audio lookup is case-sensitive. |
| 9 | API-001, API-002 | Backup history restore and archive consistency. |
| 10 | API-201 | Restoring an old backup sends you back to setup or imports another device's folder path. |
| 11 | UX-003, API-202, API-203 (+DEAD-702) | Download-era settings, the SAF repair dialog, the migration prompt and up to 2 s of extra startup time. |

## Tier 2: user-visible defects

| # | Findings | What it fixes |
|---|---|---|
| 12 | UI-101, UI-201, UX-201 | The mini player hides on pause, Back during batch progress also closes the screen behind, and the Cache page shows an endless spinner on error. |
| 13 | BUG-201, BUG-202 | Artist Popular reshuffles while the page is open, and search shows local songs while Local Library is off. |
| 14 | UX-101, DATA-002, DATA-003 | Unbounded whole-library loads, and album lookup by name instead of key. |
| 15 | BUG-101, RUST-401 (+RUST-403) | Untimed TTML lyrics, plus LRC parsing edge cases. |
| 16 | RUST-101, RUST-201 | ID3 text decoding, and the FLAC hi-res analysis window. |
| 17 | RUST-202, RUST-203, RUST-204 | CUE FILE and timestamp parsing, and library thumbnail bounds. |
| 18 | CONC-001, CONC-002 | Seek/restart races and source deletion during playback. Correctness only, with no legacy-playback rewrite. |
| 19 | SEC-001, SEC-002 | `deleteFile` path scope, and the scan-prefs read. |
| 20 | DATA-201, DATA-203, DATA-004 | Search tokenization, duplicate keep-best, and singles/albums counts. |
| 21 | UI-202, UI-401, BUG-203, BUG-204 | Verify each first; then stale selection counts, log list rebuilds and library reload edges. |

## Tier 2b: performance (measure first, then fix)

| # | Findings | What it fixes |
|---|---|---|
| P1 | PERF-401 | Add the `album_artist_norm` index; artist screens and the Artists shelf stop doing full scans. |
| P2 | PERF-501, PERF-504 | One cover file per image without fsync; incremental scans stop re-copying unchanged CUEs. |
| P3 | PERF-502 | Untagged files stop being copied whole on every scan. |
| P4 | PERF-402, PERF-601 | Genres exploded once per library version; a one-query top 20 for Artist Popular. |
| P5 | PERF-404 (with UX-104), PERF-201, PERF-602 | Dead lookup sets and wasted per-build list work. |
| P6 | PERF-405, PERF-603, PERF-604 | Home shelf caching and rebuild scope, and startup ordering. Only if measured. |

## Tier 3: cleanup

Each row is one feature-removal batch, following the `AGENTS.md` graphify-first workflow. The
tests to delete are listed in TEST-101.

| # | Findings | What it removes |
|---|---|---|
| 22 | DEAD-601, DEAD-611, DEAD-622, DEAD-633, DEAD-703 | Mornye-only collapse: non-Mornye branches, Material Expressive leftovers and the unused font. |
| 23 | DEAD-001..004, DEAD-501..504, DEAD-632, DEAD-704 | Download, provider and re-enrich services and helpers. |
| 24 | UX-104, DEAD-602, DEAD-603, DEAD-621, DEAD-631, DEAD-706 | Unused widgets and files. |
| 25 | DEAD-201..208, DEAD-301..304, DEAD-401..403 | iOS paths, dead bridge methods, and dead settings fields. Keep the JSON parse. |
| 25a | DEAD-202 tail: DEAD-902, DEAD-907, DEAD-908, DEAD-904 | Hi-Res/AC4/split-artist native code and SAF collision writers (~3,400 lines); regenerate uniffi bindings. |
| 25b | DEAD-801, DEAD-802, DEAD-803 | Download-history DB API, download-queue persistence and theme leftovers. Keep the schemas and old-key parsing. |
| 25c | DEAD-804, DEAD-805, DEAD-806, DEAD-851..854, DEAD-909 | Unused or test-only symbols, widget params and resources. |
| 25d | DEAD-901, DEAD-903, DEAD-905, DEAD-906 | Rust progress/clock modules, unused crates (`scraper`, `tz-rs`) and unused Android resources. Do this after 25a, then re-run the orphan checks. |
| 26 | DEAD-701 | Unused l10n keys. Do this last, then re-run the scan. |
| 27 | TEST-204, TEST-201, TEST-202, TEST-304 | Root skip guard, paging-test timeout, temp dir cleanup and a Kotlin unit-test script. |

Remaining P3 items (UX/a11y, PERF, minor KT/RUST/SEC) can ride along with the batch that
touches the same file.

## Product decisions (answered 2026-10-20)

- UX-205: done in `c29daef` (About credits/links/social removed).
- DEAD-705: done in `c29daef` (Search Recent list and tables removed).
- SEC-301: keep `MANAGE_EXTERNAL_STORAGE`.
- DEAD-909: keep `NativeReplayGainPolicy` for the Media3/ExoPlayer port.
