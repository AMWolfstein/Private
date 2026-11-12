# M002 — Implementation plan

## Repository evidence

Baseline 97758f89, new-workflow, clean tree. Planning-start full map succeeded:
1,782 sources, 36,693 symbols, 128,178 relationships; no partial/unindexed graph
records. Inspected root instructions, direct TOR skill, previous workflow_env.py
archive, current tool manifests/discovery and existing feature/quick records.
Gradle/CMake and policy semantics were checked from source, not inferred by graph.

Legacy environment commands were removed with workflow/. Current CodeGraph/Serena/
Bash adapters already have pinned manifests, but no combined lifecycle CLI or
tracked allocator exists. Existing records: completed native tasks T001–T003 and
standalone TOR001. Import them as M001-T001–T003 and TOR001; keep old evidence.

## Design

- Python stdlib registry + CLI at tools/workflow/work.py. Tracked authoritative
  .specify/task-registry.json, atomic local lock/reservation writes, immutable
  reservation identity and one shared TOR counter. Validate canonical record IDs,
  duplicate JSON keys, counters, completion/history and changes versus base Git.
- Root TASK_HISTORY.md is a deterministic completed-ID/title list, not a second
  manually maintained state source. Completion is declared with recorded actual
  check/PASS evidence; the helper cannot prove an independent human/agent ran.
- status/doctor/setup reuse pinned analysis packages and ignored local venvs.
  Optional Serena explicitly requested; SDK/JDK/Cargo/NDK not silently installed.
  Current adapters discover provisioned local interpreters. No app dependencies.
- Update all active instructions/templates for full IDs and allocator use. Add a
  dependency-free GitHub integrity check with base-preservation validation. Per-
  checkout locks cannot serialize disconnected clones: reconcile with latest base
  and validation; branch protection is an external repository setting, not claimed.

## Validation

Tests cover shared TOR numbers, concurrent reservations, immutable/base state,
invalid IDs/records/history, legacy migration, meaningful doctor/setup failures,
local paths and interpreter discovery. Run real local core doctor/setup and
existing tool tests. No APK/native application build needed for this tooling change.

## Constitution check

One planning commit, sequential reviewed tasks, first-action map per task; no
legacy runtime fingerprint gate. Bootstrap M002 IDs are declared here once before
the allocator exists and imported as reserved in T001; all later IDs use it.
