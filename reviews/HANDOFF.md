# Upstream port handoff

User authorization: continue all remaining PORT_PLAN batches through completion, without
asking again. This supersedes older one-batch stopping notes. Keep checks/checkpoints per
batch, all feature exclusions and no APK. No worktrees or force-push.

Current phase: batch 8 complete. Next: batch 9 (U-301 equalizer only).
Branch/repository: ccr-2fb644cd-nmesyt, /workspace/Private.
Read-only upstream /workspace/mornye-upstream at e0563ffa; divergence v5.1.1 78699a91.
Read AGENTS.md, STATE.md, PORT_PLAN.md and PORT_EXECUTION.md; status/branch/latest commit,
fetch origin and verify before edits. Graphify before editing, update after each logical port.

U-304 adds local Rewind highlights and seasonal invitations using recorded listening statistics and Mornye surfaces. U-305 adds pinned Unicode/month section headers and adaptive fast scrolling without changing the dedicated Songs/category layout or bounded paging. U-307 adapts compact launcher-player sizing, preserving existing controls/themes. U-312 bounds restoration checks, virtualizes Settings search, limits logo decoding, avoids redundant static contrast readbacks and scopes pinch updates to the grid.

Source → graph: U-304 `f4fb6794` → `39f9bf4a`; U-305 `6052f9ea` → `ef111d26` (includes U-209 cached locale formatters and U-312 pinned lists); U-307 `2c9c0305` → `e51d221c`; U-312 `c49d7af9` → `c05701ff`. Compatibility fixes `1c589407` → `4f5bc88d`; Rewind header/offline fixture fix `c3d79e0d` → final graph checkpoint (see history).

PASS: analysis clean; Flutter 1739 passed / 3 skipped / zero failures (04:10); Android unit 62 passed / 1 skipped; Rust script NOT RUN (no Rust source changes).
Graph 9020a7aa, source c3d79e0d: 23,813 unique nodes / 45,709 valid links; synchronized, existing vendor extraction warnings remain.
No dependency/schema changes or user-owned music writes. Rewind share targets and launcher resizing on physical devices NOT RUN. Initial analysis mismatches corrected using retained APIs; initial Flutter failures caught an unbounded close control and an upstream remote-source fixture assumption, both corrected before final checks. No runtime speedup measurement. Android widget visual redesign/preview intentionally excluded.
No APK, no branding/online/Material restoration or replacement engine. Physical-device
verification NOT RUN. KT-202 remains OPEN, unrelated to the planned UI ports.

Logs: /workspace/batch-8-analyze.log, batch-8-full-tests.log, batch-8-*-graphify.log;
Kotlin/Rust logs only where source changed. Exit files batch-8-flutter.exit plus relevant
native checks. See VERIFICATION.md. Docs checkpoint committed/pushed after checks; verify
HEAD against fetched origin. Latest docs SHA: git log -1 --format=%H -- reviews/HANDOFF.md.

Batch 9: owner-selected U-301 ecf594aa + 68c739df, Android DynamicsProcessing on the existing player only; no Darwin backend/dependencies. Use Mornye-only editor, preserve preset headroom/limiter choices, direct/exclusive bypass and native error reporting. Add EQ facts to U-303 audio-info sheet. Continue all remaining batches through 16. Temporary reviewed source/scripts under /tmp are preparation only until executed.

SOL-only policy; identity/effort not exposed, no model switching. Continue MEDIUM preference;
escalate reasoning for Rust/FFI/concurrency when needed. Activate
/workspace/toolchains/activate.sh; Graphify /workspace/toolchains/graphify/bin/graphify.
Existing cloud setup reused. Code → graph → docs commits; tests at batch boundaries.
