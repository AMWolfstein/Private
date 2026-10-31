---
name: plan
description: "Technical design for a feature or architecture change after its spec: writes plan.md (current system with file:line, design, decisions, constitution check, verification plan) and, for architecture changes and migration batches, runs fresh-context design reviews until two consecutive rounds are clean."
---

# Plan

You hold the context; the reviewers do not. Write plan.md so a reviewer who never saw the conversation can
understand and check it.

## Write plan.md

1. Facts first: how the current system works, with `file:line`, who calls the code you will change, and what
   tests cover it today. Start from `python3 workflow/scripts/work/work.py context "<change>" --file <path>`
   (`--depth 2` adds the channels of import neighbours), then read the code it points to; do not describe the
   system from memory, from the reference app or from the packet alone.
2. Design, in the template's rows: ownership and dependency direction, contracts across Dart, Kotlin and Rust,
   threads and lifecycle, failure and publication, data compatibility, and what gets removed with proof.
3. Decisions as `PD-n` with rationale and the alternatives considered. Prefer existing code, then Flutter,
   Android or Media3, then installed dependencies. No new layer without a boundary that needs it.
4. Constitution check: tick each article only when the plan meets it. A deviation goes in Complexity tracking.
5. Verification plan: which tests prove each FR; characterization tests before behaviour is replaced;
   device checks for the owner.
6. Open choices: anything that is the owner's call, as unranked options.

A feature-size plan can be short: "unchanged" and "none" are fine answers.

## Migration batches

- The batch order and decisions in `docs/AUDIO_ENGINE_MIGRATION.md` (section 7, then section 10.5) bind. Name
  the batch and its prerequisites in the spec. A batch whose prerequisite is not done is blocked, not reordered.
- Pin today's behaviour first: port the existing Dart tests as the specification before the Kotlin code
  (section 6.1), and run old and new on the same inputs where both exist (section 10.4: song IDs, schemas,
  backups, cover keys, tag output, CUE results must stay byte-compatible).
- Remove old code only after the replacement's acceptance passes, with a reference inventory (`work.py context
  --expand file:<path>` for importers, callers and channels, plus `rg` for strings and dynamic uses the map
  cannot see) proving nothing still uses it. Record the source commit of anything ported, and keep licence headers.

## Design review (required for architecture, optional for feature)

1. `python3 workflow/scripts/work/work.py packet --change <NNN> --out .work/review/<NNN>-design-r<N>.md`
2. Start both reviewers on the packet, each with only: "Review the packet at <path>." Do not add your opinion,
   the conversation, or what you expect them to find.
   - `goldfish-reader`: paraphrases the design and reports what it cannot understand.
   - `design-critic`: checks it against the constitution, the decisions and the real code.
   A reviewer that fails or times out has not run; retry once. It never counts as a clean round.
3. Copy each finding into `findings.md` as `### F-NNN [design rN, reviewer] title` with Severity and Status, and
   resolve it:
   - fix: edit spec.md or plan.md, and say where in Evidence;
   - contest: only with evidence the reviewer can check (file and symbol, a recorded decision);
   - escalate: the answer is outside the repository; it goes to the owner;
   - decline: nits only.
   A comprehension gap is never contested: if a fresh reader misread the plan, the plan is unclear. Never change
   a finding's severity; contest it instead.
4. `python3 workflow/scripts/work/work.py round <NNN> design clean|dirty --reviewer goldfish-reader+design-critic`. Clean
   means no open blocker or major finding in this round.
5. Repeat with a new packet. Done after two consecutive clean rounds (fresh reviewers notice different things).
   After 4 rounds, list the open findings by severity and ask the owner whether to accept, continue or rethink.

## Gate

Show the owner the plan summary and open choices. When the owner accepts, record it in `log.md` and run
`python3 workflow/scripts/work/work.py advance <NNN> tasks`. The gate refuses unfilled sections, unticked constitution
items, and, for architecture, a plan changed after its last clean review round.

## Project guidance

Read `workflow/work/guides/architecture.md` and the relevant contract in `workflow/work/guides/contracts/`.
When a design creates or moves an ownership boundary, propose its `workflow/work/architecture.json` module
(paths, responsibility, owns, may_depend_on) in plan.md; record it with `status: reviewed` only after the design
review and the owner's acceptance (schema: `workflow/work/guides/map.md`). For ports, also read `workflow/work/guides/port.md` and `workflow/work/guides/migration.md`. The migration guide carries historical references: verify the actual reference revision and accepted decisions before importing. In a new repository preserve these guides; do not rely on an absent external plan. Later explicit owner decisions and the current accepted migration plan supersede historical summaries. Record conflicts rather than silently choosing.

## Executable assurance

Fill `assurance.json` before design review: source revision, component dispositions, bridge contracts, check IDs, prerequisite change IDs and device cases. Follow `workflow/work/guides/assurance.md`; no duplicate evidence database.
