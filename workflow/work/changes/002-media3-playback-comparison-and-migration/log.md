# Log 002: Media3 playback comparison and migration

## Entries

- 2026-11-09: change created on media3-exoplayer from 933e0bd6fbc00899372a815a74ab6fffc3a5fe73; target clean before documentation. Source reference SistrumKotlin feature/media3-migration pinned to 88e59879402cd23696a222c9a395592fa7fd1ea3, clean and read-only.
- 2026-11-09: owner requested a new branch for the proposed comparison and staged migration plan, then asked about C++/FFmpeg retirement. No production implementation or retirement performed.
- 2026-11-09: matrix and E01–E12 roadmap written, including queue identity hazard, source/target evidence distinction, policy/prerequisite gates and separate FFmpeg/C++ removal inventories.

- 2026-11-09: documentation validation passed for local links, placeholders, 18 target evidence paths and 7 reference paths. Comparison committed as ceaff22f. The root comparison path is used because /docs/ is ignored by this checkout; no ignore policy changed. Production lib/android/rust_backend/extensions and the source checkout remain unchanged.
- 2026-11-09: work.py check auto reports BLOCKED/no configured domain for planning-only files; no runtime check is claimed. work.py lint reports future implementation/design/code-review gates and unfinished future tasks; the change remains a draft in plan phase. No independent review round or implementation approval is claimed.

## Close

- Drift: none in production; this is a draft planning deliverable, not an accepted or implemented player port.
- Not verified: independent design review, target builds/tests, native/core semantic parity, physical-device scenarios and all future E01–E12 acceptance. Owner-reported source device use is acknowledged separately.
- Lessons: no repeated implementation defect introduced in this documentation batch.
