# Workflow helpers

Portable Python helpers for the current Spec Kit/Ponytail/analysis setup. No old
work.py execution engine, source fingerprints, global hooks or APK build steps.
Run from the checkout; `--root PATH` can select another repository explicitly.

## Environment and status

```sh
python3 tools/workflow/work.py status
python3 tools/workflow/work.py doctor
python3 tools/workflow/work.py setup
python3 tools/workflow/work.py doctor --full
```

`status` reports branch/commit, changed paths, reserved/completed tasks, next M/TOR
numbers and history consistency; it does not allocate IDs or mark tasks complete.
`doctor` checks Git/root/ignored paths, Node/npm, pinned CodeGraph 1.6.2 and a real
Bash/TOML parser probe. Optional capabilities are reported separately. `--full`
requires availability of the app's Dart, Rust 1.99.1/Clippy, JDK 25, Android SDK/
wrapper and clang-tidy/compilation database. Availability is not successful build,
device or all-variant coverage. Doctor never installs missing toolchains.

`setup` provisions local CodeGraph via its existing npm lock and pinned parser
requirements in `.work/code-tools-python`. Already healthy packages are reused.
Optional `setup --with-serena` installs pinned semantic packages in
`.work/serena-python`; `doctor --with-serena` requires that capability. It does not
start language servers or download their SDKs. `setup --offline` only checks/reuses
existing tools; missing dependencies remain INCOMPLETE. Logs are ignored under
`.work/workflow-setup.log`. No apt/system/global agent configuration or application
dependencies are changed. Node/npm/Python and application toolchains must be
installed/activated separately. Analysis adapters automatically discover the new
managed interpreters; explicit environment overrides still win.

Core PASS excludes optional capabilities unless requested. INCOMPLETE/error returns
exit 2; a successful helper returns 0. Registry inconsistency is an error, not a
clean status. Source remains unaffected by tool setup.

## Identity reservation

The tracked authoritative file is [.specify/task-registry.json](../../.specify/task-registry.json).
Never hand-assign IDs or edit counters. Before a new checkout starts modification,
fetch/reconcile the latest task registry. These are local agent-independent commands:

```sh
# After creating the ordinary Spec Kit feature directory:
python3 tools/workflow/work.py mission new --title "Player controls" --path specs/003-player-controls
# Use the actual M ID returned, not a number copied from this example:
python3 tools/workflow/work.py task reserve --mission M003 --title "Update controls"
python3 tools/workflow/work.py task reserve --mission M003 --title "Cumulative review" --final
# Owner extra within that mission:
python3 tools/workflow/work.py task reserve --mission M003 --tor --title "Extra change"
# Independent small task:
python3 tools/workflow/work.py task reserve --title "Fix button label"
```

Mission IDs are M001, M002, etc. Regular tasks use local T counters, yielding
M003-T001, M003-T002, etc. TOR numbers are **global**: after existing TOR001, a nested
extra can be M003-TOR002 and the next standalone task TOR003. A prefix does not
permit reusing TOR001. Reservations persist even before completion and cannot be
reset by `init`. Completed/finalized missions refuse new tasks. Extras reserved
after an unfinished final task are inserted before it in tasks.md.

The allocator creates canonical task checkboxes or a standalone short record.
Fill request/baseline/acceptance/check/review details without changing the reserved
ID/title/path or fabricating completion. Use the returned path and actual ID.
Feature folder numbering and mission numbering are independent. No hidden active-
task executor is added; records still follow the existing map/review/commit policy.

## Completion and root history

After actual checks and independent PASS (at most three review results):

```sh
python3 tools/workflow/work.py task complete M003-T001 --reviewer reviewer-name --round 1 --checks "Actual checks PASS"
python3 tools/workflow/work.py validate
```

This marks that task complete, updates its checkbox/status and regenerates root
[TASK_HISTORY.md](../../TASK_HISTORY.md). History contains only completed full IDs
and names; details stay in the record. Completion evidence is a recorded declaration,
not automated proof of independent review. Do not pass invented evidence. Include
registry/history/record updates in the task's one commit, not another completion
commit. No history entry for pending/failed tasks or read-only/Git-only operations.
`history` regenerates the projection if it was edited or a write was interrupted.

## Migration, integrity and concurrent work

`init --migrate` was used once to import existing explicit records: native tasks as
M001-T001/T002/T003, completed TOR001, and this feature's M002 reservations. Old
independent evidence remains; no unrecorded past changes are invented as tasks.
For a genuinely new repository, `init` starts empty; neither command overwrites an
existing registry. Duplicate legacy TOR numbers fail before migration writes.

`validate` checks JSON duplicates/schema/counters, all task-checkbox candidates
(including malformed IDs), canonical records, completion and exact history output.
`validate --base COMMIT_SHA` additionally refuses removed/reassigned reservations,
rewritten completed history or numbers below previous counter ranges. A GitHub
Workflow identity check runs this on push/PR. Make it a required check in branch
protection to block merges; repository settings were not changed automatically.

Local atomic directory locks serialize processes in one checkout. **Offline clones
or separate worktrees can still reserve the same next number from the same Git
snapshot**: there is no remote allocator. Fetch/rebase before allocation/publishing;
base validation detects conflicts, which must be resolved without reassigning IDs
already published on the target branch. Re-reserve unmerged conflicting work with
new IDs and preserve target history. Do not force-push to bypass reconciliation.

The registry JSON reservation is persisted atomically before dependent record
writes, so a crash does not reuse a number. An interrupted record/history write
is detected by validation: restore the canonical record from its reservation and
saved task evidence, then regenerate history. No automatic deletion/reuse occurs.
A stale `.work/task-registry.lock` is removed only after confirming no helper is
active. Do not run setup/allocations concurrently during dependency provisioning.

## Validation

Run `python3 -m unittest discover -s tools/workflow -p 'test_*.py' -v`, then the
existing tools/codegraph suite. Identity CI needs only Python/Git, no SDKs/packages.
See [M002 evidence](../../specs/002-workflow-lifecycle/task-log.md) for actual results
and limitations. This is instruction/tooling support, not an adversarial sandbox
against someone editing validators or bypassing repository checks.
