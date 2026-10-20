# Upstream port handoff

User authorization: continue all remaining PORT_PLAN batches through completion, without
asking again. This supersedes older one-batch stopping notes. Keep checks/checkpoints per
batch, all feature exclusions and no APK. No worktrees or force-push.

Current phase: batch 10 complete. Next: batch 11 (MORN-006..012; FIX_PLAN M3+M4).
Branch/repository: ccr-2fb644cd-nmesyt, /workspace/Private.
Read-only upstream /workspace/mornye-upstream at e0563ffa; divergence v5.1.1 78699a91.
Read AGENTS.md, STATE.md, PORT_PLAN.md and PORT_EXECUTION.md; status/branch/latest commit,
fetch origin and verify before edits. Graphify before editing, update after each logical port.

MORN-001..005 and MORN-017 align retained collection UI behavior: album selection owns the toolbar and hides playback actions; playlist/Loved use shared circular toolbar controls and collapse titles; hydration shows skeletons instead of empty flashes; current rows pause/resume without queue restart. Artist/album loading/error/empty presentation now uses retained Mornye primitives and hides an empty Popular heading.

Source `bc983981` → graph `afcb349a`; fixture duration `b55043ba` → `36cdf5d4`; hydration fixture isolation `b602dfb3` → `de2c48ba`, duplicate override correction `ad7e26eb` → `d6b8c566`. Upstream-latest collection patterns inspected at e0563ffa; existing offline behavior retained.

PASS: analysis clean; Flutter 1759 passed / 3 skipped / zero failures (04:13); Kotlin checks NOT RUN (no Kotlin source changes); Rust script NOT RUN (no Rust source changes).
Graph d6b8c566, source ad7e26eb: 23,954 unique nodes / 45,967 valid links; synchronized, existing vendor extraction warnings remain.
Six new light/dark collection-state regressions cover selection exit, hydration and current-row toggling. Initial fixture failures were missing duration and duplicate provider setup; corrected before final verification. No dependencies, schemas, music-file writes, native changes or APK. Physical visual checks NOT RUN.
No APK, no branding/online/Material restoration or replacement engine. Physical-device
verification NOT RUN. KT-202 remains OPEN, unrelated to the planned UI ports.

Logs: /workspace/batch-10-analyze.log, batch-10-full-tests.log, batch-10-*-graphify.log;
Kotlin/Rust logs only where source changed. Exit files batch-10-flutter.exit plus relevant
native checks. See VERIFICATION.md. Docs checkpoint committed/pushed after checks; verify
HEAD against fetched origin. Latest docs SHA: git log -1 --format=%H -- reviews/HANDOFF.md.

Batch 11: metadata header genre/year, localized duration footer and no duplicate header counts; CUE Play-all starts at a real playable row; correct ReplayGain section label. Artist buttons share size/tint, slot-specific placeholders, 280 collapse threshold, Mornye Popular rows and responsive album cards with year/local track counts. Singles still derive ONLY from explicit total-track tags=1; no EP type is stored in browse entries, so do not invent it from downloaded file counts. Prepared /tmp/port_batch11.py is unexecuted and must be reviewed/verified. Continue all remaining batches through 16.

SOL-only policy; identity/effort not exposed, no model switching. Continue MEDIUM preference;
escalate reasoning for Rust/FFI/concurrency when needed. Activate
/workspace/toolchains/activate.sh; Graphify /workspace/toolchains/graphify/bin/graphify.
Existing cloud setup reused. Code → graph → docs commits; tests at batch boundaries.
