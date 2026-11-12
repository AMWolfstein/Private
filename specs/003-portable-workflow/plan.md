# M003 — Implementation plan

## Repository evidence

Baseline c5c8781b, new-workflow, initially clean. First full map for this session
passed: 1,787 indexed sources, 36,814 symbols, 128,522 relationships; no partial/
unindexed graph records. The request expanded before any quick task was reserved,
so this is a planned M003 feature, not an abandoned TOR. Existing counters were
validated against fetched origin before reservation.

Inspected setup/doctor/status, quick-task policy and existing history/registry.
Current canonical tools are tools/workflow, tools/codegraph, tools/ponytail; setup
only installs packages, never bootstraps root history or support files. CLI default
root currently assumes two directory levels; codegraph adapters assume their own
two-level path. Root Spec Kit script/skill layout must continue to work.

## Design

1. Move helpers to workflow/work.py etc.; analysis tools to workflow/codegraph and
   Ponytail provenance to workflow/ponytail. Update executable/active instruction/
   CI references and helper default root. Historical task evidence keeps old paths
   as historical evidence. Keep actual registry/history/records outside distribution.
2. Ship workflow/assets defaults for root .agents/.specify and integrity CI,
   excluding project registry, task records/history and local validation reports.
   Setup installs missing assets only, appends a small portable AGENTS entrypoint
   if necessary, and safely ignores managed caches. Existing support files survive.
3. Bootstrap history with exclusive creation; never rewrite existing history.
   Initialize empty local identity state only for an unambiguous fresh project.
   With valid existing registry, reconstruct missing history from actual local
   completed records. Inconsistent/ambiguous existing state stays untouched and
   incomplete, requiring explicit reconciliation. Offline setup also prepares
   local support/history but never downloads packages.
4. Comprehensive workflow/README documents all operations/rules. Cache installs
   remain local; explicit environment overrides and protected app toolchains stay.

## Validation

Existing helper + analysis suites; relocation command/path smoke; missing/existing/
Unicode history, repeated/offline/concurrent setup; asset/state-copy boundaries;
fresh copied workflow in isolated Git repo; real core setup reuse and identity CI
validation. No full application builds or runtime changes necessary.

## Constitution

One planning commit, first-action map per task, independent review max three rounds,
one task commit and final cumulative review. Preserve unrelated files. This feature
is authorized for implementation; publishing is reported separately unless requested.
