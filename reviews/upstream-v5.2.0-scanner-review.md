# Scanner recovery and notification-ordering comparison

Status: **comparison complete; implementation pending**. One bounded work unit, 2026-10-19.
Upstream source: `378c8f374987c6a8a8f8cbf6330736f136414d94` (14 changed paths).
Local source: `2b323612a7e473ef9a4e5d6a48ebb071add25924`, unchanged at review entry `f0b7b114068ecb37e3aa53398d2311ae8b2504f0`.
Content baseline/target remain as pinned in [evidence.json](upstream-v5.2.0/evidence.json).

## Corrected finding

The initial audit correctly identified fallible error persistence before failure notification, but its implication of a permanently stuck `isScanning` state was too broad. Current `startScan` has an **outer finally** (provider lines804–818) that resets the scanning/admission fields and completes ownership. If `_runScan`'s catch fails to save `lastScanError`, the original failure notification and in-memory source error are skipped and the public scan future rejects with the secondary failure; `isScanning` eventually clears when cleanup returns. A slow/hung persistence call can delay that cleanup. No permanent stuck-state reproduction was performed.

The right fix is to publish the original failure in memory and notify independently of best-effort persistence, stop progress before cleanup awaits, and preserve final ownership cleanup. Do not replace the existing outer finally.

## Dependency and control-flow evidence

Graphify query `_runScan` identified the retained provider. A path query with qualified symbols initially found no directed path; retrying `--undirected` found `LocalLibraryNotifier ←defines— local_library_provider.dart —references→ ProgressStreamPoller`. This establishes a file reference, not a verified call edge. Source inspection supplies the following call-flow evidence. Graph source remains `6ac8efd0`; synchronization commit `81577e50`; no graph/source mutation.

| Current path / anchor | Verified role / local behavior | Upstream mapping / decision |
|---|---|---|
| `lib/providers/local_library_provider.dart` build/load (193–321), startScan/_runScan (773–1293) | Disposal cancels native work, stops poller; source configuration is published early. One admitted scan owns `_scanCompletion`, cancellation flags and request ID. Outer finally releases ownership | Upstream provider+scan parts map to this monolith. **ADAPT behavior**, do not port splits |
| Provider catch/finally (1244–1293) | Source error DB update and summary refresh precede state reset/failure notice; service stop precedes poller stop | Move failure visibility before best-effort save; stop poller before awaiting notification drain/service stop; preserve final ownership/marker cleanup |
| Provider progress (1308–1364), pause/cancel/resume/wrappers (1398–1555) | Progress stops at cancellation/finalization/terminal replay on callback entry. Already-started notification futures can outlive stop; independent wrappers have no queue | **ADAPT serialized notification tail**, execution-time progress/lifecycle checks, ordered pause/resume/service transitions |
| `lib/utils/progress_stream_poller.dart` _runGuarded/stop | Generation invalidates pending fetches after stop, but cannot revoke an `onProgress` callback already awaiting notification delivery | **ALREADY IMPLEMENTED fetch generation protection**; do not rewrite shared poller |
| `lib/services/notification_service.dart` background work and scan methods | Foreground service handles progress on Android; plugin handles terminal/paused notices, with initialization/permission awaits. Errors caught by provider wrappers | Serializing messages matters even with current callback guard. Keep IDs/kind/permission behavior; no package change |
| `lib/main.dart` 458–505 | Auto-scan returns early when off; enabled auto-scan recognizes active source marker and calls startSourceScan before ordinary cadence checks | Existing automatic continuation is **ALREADY IMPLEMENTED**; add reporting independently, not a new auto-resume path |
| `lib/utils/local_library_scan_prefs.dart` | Active source key and last scan timestamp exist; no run-start/recovered keys | Additive private run/ack markers belong to B01b; no collection/metadata migration |
| `lib/services/platform_bridge.dart` 943–990 | Stable hash-derived private NDJSON path resumes scans. Explicit `forceFullScan` intentionally deletes old private NDJSON/state, not automatic recovery | Preserve this distinction; reporting must never request forceFullScan or delete checkpoints |
| `MainActivitySafScan.kt` checkpoint helpers (408–458), full scan (850 onward) | Private `.state` plus NDJSON reconciliation; cancellation retains partial output | Existing scanner behavior retained; no checkpoint format/walker changes |
| `LibraryDatabase.replaceSourceScanFile` / `LibraryNativeAdapter._import/_publish` | Cancellation and source-path/enabled checks protect publication; private native commit is not live publication; publish uses owner transaction | **ALREADY IMPLEMENTED safeguards**; no ingestion or DB schema change |
| `MainActivity.kt` onDestroy (756–777), scan/channel handlers (1529–1640) | Activity recreation stops progress stream, preserves process/shared-engine backend. Scan pause/cancel run off UI thread | Do not equate Activity recreation with process death or add backend shutdown |
| `BackgroundWorkService.kt` companion start/update/stop | Work map is keyed by kind; Android service notification 1002 differs from plugin scan ID3. Late update ignores inactive kind | Preserve service/output boundaries; host plugin mocks do not prove Android notification ordering |
| `lib/screens/settings/library_settings_page.dart` source item (858–905) | Shows generic failure status, not actual reason | Small Mornye reason display can accompany B01b, no upstream Expressive/layout import |

## Hunk decisions and boundaries

All decisions trace to the same full upstream SHA above. Overall inventory classification remains **ADAPT**; do not cherry-pick it.

| Behavior | Classification | Benefit / complexity / risk | Required gate |
|---|---|---|---|
| Failure visibility despite error-save failure; poller stopped before final awaits | ADAPT, B01a | Preserve original diagnostic/notification; small; medium async-order risk; HIGH effort | Fault-injected scan error plus DB save/summary failures; source counts unchanged; scan future completes per existing handled-failure contract |
| Chained scan notices with error-resilient tail; terminal notice follows older progress | ADAPT, B01a | Avoid delayed progress overwriting terminal/paused notice; small–medium; medium risk; HIGH | Completer-controlled progress/cancel/pause/failure/completion and delivery rejection; drain before service stop/admission release |
| Run markers and single-flight interrupted reporting even when auto-scan off | ADAPT, B01b | Explain interruption without changing resumption policy; medium; medium/high lifecycle risk; HIGH | Startup/manual-start race; old marker; duplicate restarts; missing source; prefs/DB failures; retained rows/checkpoints and existing auto-scan cadence |
| Per-source readable error text | ADAPT, B01b | Useful local diagnostic; small; low UI risk; MEDIUM | Mornye light/dark, long text/RTL; generic status still shown; no removed settings restored |
| Android exit matching / API30 reader + channel | ADAPT with additional safeguards, B01c | Optional local OS diagnostic, no scanner behavior change; medium; medium native/API risk; HIGH | API24/29 safely return no info; exact package/process + timestamp; unknown reason; absent/failed ActivityManager; diagnostic failure cannot fail library load |
| Upstream split-provider/MainActivity architecture | DEFER wholesale import | Unnecessary prerequisites in fork; avoids unrelated refactoring | Map channel into existing dispatch and allowlist if B01c implemented |
| Media mutation, index publication, checkpoint format/force-rescan policy | REJECT as part of this batch | Not required by upstream fix | Leave user files, deletion/replace transactions and native scanner unchanged |

## Minimal implementation plan, in order

### B01a — next invocation, implementation only

Touch `lib/providers/local_library_provider.dart` and meaningful tests (primarily `test/library_scan_scheduling_test.dart` and pause tests). No Kotlin, Rust, bridge, preference, settings or dependency edits needed.

1. Add one notifier-owned `Future<void>` tail with recovered-error continuation, following upstream's `_queueScanNotification` pattern. Callers still log failures; one rejected notification cannot poison later terminal/cleanup operations.
2. On non-cancellation scan failure, immediately set non-scanning/non-finalizing state and copy the original error into the matching source, stop polling, then enqueue the failure notice. Wrap DB error persistence/summary refresh in a separate catch that logs the secondary failure without replacing the original. Preserve the outer admission-release finally, scan result counts, paused flag cleanup and active-source marker clearing.
3. Route progress, pause, paused-notice clearing and terminal delivery through the same tail. Check mounted/active/cancelled/paused/finalizing status **when queued progress executes**, before reading notifier state or posting, not only at callback entry. Existing scan admission prevents the next scan until the old tail and cleanup complete; avoid adding a new persisted run format here.
4. Stop progress before final drain; drain error-resilient tail before ending scan background work. For pause, drain older progress before releasing background work and posting paused notice; for resume/finalization, reacquire work before clearing paused notice/releasing native pause. Keep ordering deterministic under a pending pause request and later cancel/terminal result; recheck mounted/active conditions after awaits. Do not queue an operation that recursively awaits its own notification tail. Apply this locally, not by serializing unrelated background-work kinds.
5. Disposal must invalidate pending progress without reading disposed state. Existing native cancellation/poller teardown remain. Pending notice failures must not block ownership completion. Do not claim timeout/hung-plugin resilience: upstream's unbounded platform await has no timeout, and adding a generic timeout policy is not justified in this small batch.

Tests must exercise output ordering rather than only mirror private implementation. Extend the fake DB with error-write and refresh failures and correct lastScanError copy semantics. Register the Android notification plugin in the relevant test process and initialize strings so delivery assertions cannot pass through swallowed LateInitializationError. Use Completers/events and bounded waits, not real sleeps. Keep the singleton initialization stable across fixtures and reset test platform/mocks in teardown.

Acceptance matrix:

- original scan failure + failing error-save: original source reason/notification visible, previous track counts retained, no leaked secondary rejection, ownership released and later scan admitted;
- queued/in-flight progress then failure, completion or cancel: terminal last; later progress suppressed; notification rejection does not prevent terminal attempt or service cleanup;
- progress then pause/resume, including delayed native pause and cancellation: no paused/progress notice after terminal and no reacquisition of work for an ended/disposed scan;
- cancellation/disposal in preflight/native/finalization and existing committed-index behavior stay correct;
- progress fetch after stop remains suppressed by existing poller behavior; do not rewrite it.

Run `flutter analyze`, then `flutter test test/library_scan_scheduling_test.dart test/library_scan_pause_test.dart test/notification_service_test.dart`. Add other targeted tests only for changed call sites. Android foreground service ordering remains a device/instrumentation verification gap unless a small existing supported seam can cover start/update/stop; Linux `Platform.isAndroid` stays false even when `debugDefaultTargetPlatformOverride` is Android. No APK required for B01a. Code → Graphify update/graph commit → report checkpoint → push → stop. Do not implement B01b/B01c during B01a.

### B01b — later bounded implementation

Use current active-source marker, additive started-at and acknowledged-recovery keys; one recovery future shared by initial load/manual start. Preserve early source configuration publication and admission, and run reporting independently of auto-scan mode. Keep source identity and private checkpoint files unchanged. Reporting alone does not start/resume scanning; enabled auto-scan's existing startSourceScan path does that.

Persist a start token/time before new work; clear stale recovery acknowledgement on new run. At cleanup, clear keys only when they still belong to this run. Validate nonblank marker/source existence; do not recreate missing sources or enable disabled/offline sources during reporting. Legacy markers without time receive generic interruption text, never a fabricated crash reason. An old marker proves unfinished cleanup, not necessarily process death (hot restart/provider recreation can interrupt work in a live process). Explicitly retain this distinction and avoid stopping a newly admitted/live owner. Keep only one same-instance recovery attempt after a save failure, with cross-restart retry/acknowledgement policy tested; do not silently acknowledge a failed error persistence as durable success.

After original interruption is visible, error persistence may fail without failing load or losing the notice. Preserve user data and native resume artifacts. Actual reason display uses retained Mornye primitives/friendly-error handling; add localization via repo workflow. No metadata/schema migration. Recovery must not erase a newer run's marker while awaiting diagnostics. Required tests: off/on_open/daily/weekly, startup+manual race, disabled/missing source, legacy marker, successful/error-save failure duplicate restarts, no record deletion or force-rescan, mounted checks.

### B01c — later bounded implementation

Add optional Android `LibraryScanExitInfo` helper with API30 guard and a single bridge method in existing MainActivity dispatch/allowlist. Do not copy upstream MainActivity splits or generic crash banner. Return no info below30/no timestamp; match main package process and exit timestamp >= run start. Treat low memory/ANR/user stop as their own labels, never imply all interruptions are native crashes. Bound description as upstream does; guard service lookup/query exceptions and stale async results so optional diagnostics cannot block or corrupt recovery. No new permission/dependency, device upload, file-write operation or trace collection required. Tests include matching boundaries, side-by-side runtime package, unknown reason, null/exception/no match, API guards and Dart decode/platform channel contracts. JVM constant/matcher tests alone do not execute Android ActivityManager/API24 class loading; record device/emulator checks separately.

## Executed verification and limits

- **PASS:** existing focused baseline: `flutter test test/library_scan_scheduling_test.dart test/library_scan_pause_test.dart test/notification_service_test.dart --reporter expanded` — **20 passed**, zero failures (host Linux). Captured output `/workspace/upstream-520-scanner-baseline-tests.log`.
- Test log contains swallowed notification `LateInitializationError` warnings in scheduling/pause harnesses and an expected mocked native pause failure. This is a coverage weakness, not a passing notification-ordering test. New fault/race tests are **NOT RUN / not yet written** in this comparison unit.
- Graphify scoped query/path **PASS** with reference-vs-call limitation above; existing graph JSON verified by checkpoint verifier. No update required for reports only.
- Flutter analysis/full suite, new regressions, Rust/Kotlin checks, Android device behavior and APK build **NOT RUN** this unit; no code changed. No performance claim.
- Existing checkpoint verifier and Git staged diff checks must pass before committing these review changes. No environmental setup/configuration change needed; current tools ran focused baseline tests.

No implementation blocker for B01a. B01b/c remain gated on their own tests/lifecycle safeguards. The next exact work unit is **B01a implementation only**, HIGH effort. Final compatibility report remains pending completion of the wider audit/backports.
