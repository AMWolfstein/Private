# Resume upstream v5.2.0 audit

## Read first

Read `AGENTS.md`, `LOCAL_OFFLINE_MIGRATION_PLAN.md` Progress, `reviews/STATE.md`, the [audit](upstream-v5.2.0-audit.md), [backlog](upstream-v5.2.0-backlog.md) and [verification](VERIFICATION.md). Inspect `git status --short --branch` and latest commits before work. Preserve unrelated changes. Execute **one bounded work unit per invocation**.

## Repository and checkpoint

- Branch: `review/upstream-v5.2.0-discovery`; origin `https://github.com/AMWolfstein/Private.git`.
- Source checkpoint on entry: `2b323612a7e473ef9a4e5d6a48ebb071add25924` (docs after code `6ac8efd0` and graph `81577e50`). No application changes in discovery.
- Audit checkpoint SHA: pending first commit; replace this line after committing inventory.
- Push status: PENDING; do not claim another agent can access this branch until push succeeds.
- Use `git log -3 --oneline` / `git rev-parse HEAD` for the actual latest tip; checkpoint files record the last known parent/receipt, not a self-referential commit hash.

## What is established

Local history begins with parentless root `47298e55b1eef2cfdbef1f7b80570a164bfa2f3b`; repo is not shallow and `git merge-base` to upstream release exits 1. Baseline is **content equivalent**, not claimed ancestry: `5a8952659b247fd95f1914a56db60825657fe26d` differs from local root only by four omitted docs/vendor `.orig` files. v5.1.1 tag alone additionally differs in apps.json. Target is v5.2.0 **peeled** `22f3ec52f9bd1e57f661ca0b17e3aaa34b0e8ae8`; its fetched ref is `refs/remotes/upstream-audit/v5.2.0` (annotated tag, use `^{commit}`). Fetch this explicit tag again if the review environment lacks the local remote ref; do not compare moving upstream main. Do not invent a merge base.

238 commits (one merge), 858 paths indexed in `reviews/upstream-v5.2.0/`; 17 focused source-reviewed, one partial, 220 path-only. Classification counts and scope are in STATE/audit and reproducible by review verification script. **No backport implementation, dependency migration or APK build.** No final report yet: final phase is pending.

Seven narrowly scoped ADAPT candidates; no unchanged wholesale ADOPT. All local path presence is evidence of existence only, not semantic equivalence. Untouched refactor/test/docs entries are provisionally deferred; unknown functional work remains INVESTIGATE. Remaining comparison coverage, security and resolved dependency checks are incomplete.

## Next exact work unit — HIGH

**Comparison only: scanner recovery and notification ordering for upstream `378c8f374987c6a8a8f8cbf6330736f136414d94`.** Use Graphify first to map current `local_library_provider.dart`→notifications/platform bridge→Android scan/lifecycle and persistence. Upstream has split provider/native helper files; current provider is monolithic. Do not port the splits.

Current catch around lines1253-1270 awaits DB source-state persistence/refresh before clearing `isScanning`; independent notification methods around1490-1554 have no serialized tail. Inspect current behavior against upstream cleanup/error persistence separation, serialized progress/terminal futures, recovery markers/start timestamp and API>=30 exit-reason matching. Resolve cancellation/disposal, auto-scan disabled restart, checkpoint preservation, source IDs, finish polling/drain order, and how to inject failures. Produce minimal implementation/test plan; do not start other subsystems. B01 may be split into error-ordering and recovery implementation units in a later invocation.

A potential output-failure→completion defect (`f426b2d1`, I02/P0 investigation) is not yet reproduced. It is separate from planned scan comparison and does not authorize broad player rewriting. SAF sidecar parent fix (`186c66ae`) needs retained-editor reachability/safe-write proof. FLAC decoder replacement/EQ/haptics/complex AutoMix remain deferred.

## Graph, tools and verification

- Existing graph: `graphify-out/graph.json`; last synchronized code `6ac8efd0`, graph commit `81577e50042177e8e9c71a81402efd362df69d6b`. Source unchanged during this audit, graph CURRENT, no regeneration needed for docs. Query output was used for retained scanner/metadata/artwork/lyrics dependencies. Do not base architectural decisions solely on stale graph if later code diverges.
- Executable: `/workspace/toolchains/graphify/bin/graphify`. Repo mechanism is `graphify update .` after code changes, then separate graph commit. `source /workspace/toolchains/activate.sh` sets existing Flutter/Rust tools if necessary; don't invent Graphify/model commands.
- Read-only public upstream fetch succeeded with inherited managed network configuration. No credentials/secrets were copied into reviews. Existing toolchain/environment setup required no changes.
- Review-only verification: `python3 reviews/upstream-v5.2.0/verify_checkpoint.py`; see VERIFICATION for exact coverage and unexecuted checks. Runtime tests have not been rerun for this docs-only checkpoint.
- Follow AGENTS code→graph→docs commit separation on implementation. This unit is docs/evidence only, so no empty source/graph commits. Push review branch without force, not main.

## Policy/model continuity

User requested SOL exclusively and adaptive effort. Runtime model ID/effort controls are not exposed; **not independently confirmed**, no model switch or delegation performed. Recommend HIGH for next scan/lifecycle comparison (Rust/FFI/write-integrity investigations HIGH, exceptional corruption conflicts EXTRA HIGH; later docs/commits LOW).

Mornye is sole production theme, but existing `material_ui`, `material_3_expressive`, `material_color_utilities` and helper imports are a real pre-existing discrepancy. Do not claim Expressive is entirely absent; do not restore it or remove retained shared primitives casually. No online features, removed settings/routes/Wishlist/conversion, streaming/downloading/provider credentials or remote artwork. Preserve offline tags/editing, local lyrics/artwork, playlists/Loved Songs/Genres, stats, Rust/native integration and future Media3 migration flexibility. No runtime performance or regression-free claim without evidence.
