---
name: spec
description: "Planning and discussion with the owner, and the first step of features and architecture changes: writes spec.md (what and why, user scenarios, FR/SC requirements), asks the few clarifying questions that matter, and checks the requirements' quality before any design or code."
---

# Spec

The spec is the shared document for a discussion. It says what the owner wants and why, never how.

## Create

`python3 scripts/work/work.py new "<short English title>" --size feature|architecture` creates
`work/changes/NNN-slug/` with `spec.md`, `plan.md`, `tasks.md`, `findings.md` and `log.md`.

## Write spec.md

1. Read the binding decisions first: accepted specs in `work/changes/` that touch the same area, and for engine work
   `docs/AUDIO_ENGINE_MIGRATION.md` (decisions D1–D7 and the batch order). Cite the ones that apply under
   "Binding decisions". If the request conflicts with one, stop and ask the owner which wins.
2. Read the current behaviour in the code so the scenarios describe the real starting point.
3. Fill the template:
   - User stories by priority. Each one is testable on its own, with Given/When/Then acceptance.
   - Edge cases: empty and huge libraries, offline, permission revoked, cancelled midway, app killed, RTL,
     slow devices, old backups and settings imports.
   - `FR-001` style requirements ("The app MUST …") and measurable `SC-001` success criteria.
   - Out of scope, and Assumptions for the defaults you chose instead of asking.
   - Delete sections that do not apply rather than writing "N/A".
4. No implementation in the spec: no classes, files, packages or APIs.

## Clarify

- Mark at most 3 `[NEEDS CLARIFICATION: …]` items, only for choices that change scope, data safety or user
  experience and have no reasonable default. Priority: scope, then data and privacy, then UX, then technical.
- Ask one question at a time, at most 5 in a session. Routine questions: give a recommended answer and the
  options. Product or architecture trade-offs: up to three options with mechanism, trade-offs and failure
  conditions, unranked.
- Record each answer under "Clarifications" as `- Q: … → A: …`, apply it to the sections it affects, replace any
  text it contradicts, and remove the marker.

## Check the requirements

Before moving on, read the spec as a test of the requirements, not of the code:
- Are the scenarios, failures, cancellation, permissions and offline behaviour specified for each story?
- Is every requirement unambiguous and checkable, with no "fast", "nice" or "robust" left unmeasured?
- Do any two requirements conflict, or repeat each other in different words?
- Does every requirement trace to a story, and every story to at least one requirement?
Fix what fails. Then show the owner a short summary in their language and the open questions.

## Gate

`python3 scripts/work/work.py advance <NNN> plan` refuses while markers remain or there is no FR or acceptance
scenario. When the owner is only discussing, stop here and keep refining the spec with them.
