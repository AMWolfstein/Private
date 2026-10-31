# Sistrum workflow

A portable, project-specific engineering workflow for Flutter/Dart, Kotlin and their Android bridge. No Desloppify installation, score, Spec Kit CLI, runtime service or third-party agent plugin is required. Skills guide reasoning; ordinary analyzers, tests and independent reviews supply evidence. This is a workflow starter, not an implemented player or a promise to find every bug.

## Use in a new repository

1. Copy **the contents** of this directory into the new repository root, including `.agents/`. Do not leave them inside a nested `new workflow/` directory. Merge an existing `AGENTS.md` rather than silently overwriting it. No installer is needed.
2. Open that repository in an agent that reads `AGENTS.md`. Say: **“Initialize this repository using the Sistrum workflow.”** The agent loads `.agents/skills/sistrum-workflow/SKILL.md`, inventories actual code and tools, and completes `workflow/STATE.md` and `workflow/verification.json`. An empty repository is not assumed to contain a Flutter app or a Gradle wrapper.
3. Supply the actual reference checkout/commit when porting. The historical reference in `workflow/migration.md` is provenance, not a fetched or verified source tree.
4. Use normal requests: “Continue the next Media3 batch”, “Port metadata reading”, “Fix cancellation”, “Review playback”, or “What remains?”. No named skill invocation is needed on hosts that honor the entry instructions.
5. Before trusting automation, run `python3 -m unittest discover -s scripts/tests -v` and `python3 scripts/workflow.py validate`.

On a host that does not read `AGENTS.md`, explicitly configure its project-instructions entry to read this file. There are no installed hooks or always-running agents. If fresh isolated review contexts are unavailable, record that limitation; do not call self-review independent review. CLI profiles do not invoke AI, install tools, build APKs, publish, or push.

## What happens per task

Read state/contracts → discover affected callers and risk → specify substantial work and clarify material unknowns → design only when needed → map requirements to tasks/checks → consistency review → implement → verify/review → compare delivery to requirements → checkpoint evidence and state.

Small changes stay small. Architecture and migration work get a design and isolated review. No file-size quota, forced wrapper count, automatic split, score or mandatory swarm. `part of` files are one Dart library. Review responsibilities and dependency direction.

Spec Kit's method is integrated into the same automatic entry: say “Add a sleep timer” or “Port codecs” and the agent loads `sistrum-spec` when warranted. It defines observable acceptance cases, links them to tasks and checks, catches contradictions before implementation, then checks for missing work afterward. A clear bug fix uses its existing acceptance statement; a read-only review does not create a feature or start a port. Existing policies provide the constitution role. No upstream commands, hooks, branch creation or second task database are installed. See `workflow/spec-driven.md` for the precise mapping and limits.

## Contents

- `AGENTS.md`: automatic entry and persistent authority rules.
- `.agents/skills/`: seven focused skills loaded on demand, including `sistrum-spec`.
- `workflow/architecture.md`, `quality.md`, `contracts/`: target architecture, review lenses and behavioral contracts.
- `workflow/migration.md`: normalized Media3/backend sequence, owner decisions and unresolved choices.
- `workflow/spec-driven.md`: Spec Kit adaptation, artifact sizing, traceability and convergence rules.
- `workflow/STATE.md`: current readiness, not historical success copied from another repository.
- `workflow/templates/`: spec, task, finding and design records. Copy only when needed; keep one task list per feature/batch.
- `scripts/workflow.py`: advisory routing, explicit check execution, evidence freshness and package validation. Python standard library only.
- `workflow/verification.json`: commands and prerequisites. Android module/task names must be checked during bootstrap.

## Commands (from the destination root)

```sh
python3 scripts/workflow.py route --intent 'Port playback to Kotlin' --paths android/app/src/main/kotlin/Player.kt
python3 scripts/workflow.py plan --profile bridge
python3 scripts/workflow.py run --profile workflow
python3 scripts/workflow.py run --profile flutter
python3 scripts/workflow.py run --profile bridge
python3 scripts/workflow.py fresh .workflow-runs/latest.json
```

`route` is a conservative keyword/path suggestion, not architectural discovery; the agent must expand it from real callers. `plan` never executes checks. `run` returns nonzero for failed, missing, timed-out or unconfigured checks and stores logs plus a source fingerprint. A green profile proves only those commands exited successfully. It does not approve the task, prove coverage, or satisfy device/independent review gates. `fresh` verifies evidence still matches the working tree; it does not re-run tests. Keep `.workflow-runs/` local; checkpoint concise results with the task when needed.

For Android, configure verified module-specific JVM tests and compilation commands. Detekt is optional until configured; Android Lint and tests remain required. Device evidence is recorded separately with hardware, OS, build and results. To add CI, call the same profiles after provisioning the pinned toolchain; no GitHub workflow is installed before the new build layout exists.

See `workflow/VALIDATION.md` for what has actually been tested in this starter. See `workflow/SOURCES.md` for conceptual sources and migration provenance.
