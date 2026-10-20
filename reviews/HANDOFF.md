# Upstream port handoff

User authorization: continue all remaining PORT_PLAN batches through completion, without
asking again. This supersedes older one-batch stopping notes. Keep checks/checkpoints per
batch, all feature exclusions and no APK. No worktrees or force-push.

Current phase: batch 11 complete. Next: batch 12 (MORN-013..016; FIX_PLAN M5+M6).
Branch/repository: ccr-2fb644cd-nmesyt, /workspace/Private.
Read-only upstream /workspace/mornye-upstream at e0563ffa; divergence v5.1.1 78699a91.
Read AGENTS.md, STATE.md, PORT_PLAN.md and PORT_EXECUTION.md; status/branch/latest commit,
fetch origin and verify before edits. Graphify before editing, update after each logical port.

MORN-006..012 adapt local album metadata and artist presentation: genre/year metadata, localized footer duration, first-playable Play-all, ReplayGain section labeling; matching artist controls, slot-specific placeholders, 280px collapse threshold, compact Popular rows and responsive album cards with year/local track counts and explicit single badges.

Source `df09d3ea` → graph `496dd75b`; shelf lint correction `2a6ea366` → `d1dd2638`; CUE-fixture real-song identity correction `b1fd7886` → `ff70d508`. Upstream-latest artist card/row patterns inspected at e0563ffa; adapted to retained local data and menus.

PASS: analysis clean; Flutter 1759 passed / 3 skipped / zero failures (04:13); Kotlin checks NOT RUN (no Kotlin source changes); Rust script NOT RUN (no Rust source changes).
Graph ff70d508, source 2a6ea366: 23,960 unique nodes / 45,975 valid links; synchronized, existing vendor extraction warnings remain.
Retained playback regressions now begin with a virtual CUE row and compact release-date metadata, covering both themes; first real-song identity remains explicit in later fixture checks. Artist visual/device checks NOT RUN. Single badges require explicit total-track tags=1. No EP type exists in the local browse model/database, so EP badges are omitted rather than inferred from file counts; EPs remain under Albums. No dependencies, schemas, music-file writes, native changes or APK.
No APK, no branding/online/Material restoration or replacement engine. Physical-device
verification NOT RUN. KT-202 remains OPEN, unrelated to the planned UI ports.

Logs: /workspace/batch-11-analyze.log, batch-11-full-tests.log, batch-11-*-graphify.log;
Kotlin/Rust logs only where source changed. Exit files batch-11-flutter.exit plus relevant
native checks. See VERIFICATION.md. Docs checkpoint committed/pushed after checks; verify
HEAD against fetched origin. Latest docs SHA: git log -1 --format=%H -- reviews/HANDOFF.md.

Batch 12: owner-approved tonal Loved/Add-to-playlist controls with error tint and existing loveAllTracks feedback; one shared effective artwork source for hero/surface/palette, with Loved heart using neutral artwork-free surface. MORN-015 already implemented by U-210 c2f38c86; verify and resolve without duplicate code. MORN-016 clamp segmented height to >=56, update dark red and choose onPrimary by luminance. Prepared /tmp/port_batch12.py is unexecuted; review before use. Continue all remaining batches through 16.

SOL-only policy; identity/effort not exposed, no model switching. Continue MEDIUM preference;
escalate reasoning for Rust/FFI/concurrency when needed. Activate
/workspace/toolchains/activate.sh; Graphify /workspace/toolchains/graphify/bin/graphify.
Existing cloud setup reused. Code → graph → docs commits; tests at batch boundaries.
