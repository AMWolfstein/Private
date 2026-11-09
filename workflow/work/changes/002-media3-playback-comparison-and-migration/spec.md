# Spec 002-media3-playback-comparison-and-migration

Status: Draft planning deliverable; implementation not authorized by this artifact
Created: 2026-11-09
Input: The owner requested a new branch named `media3-exoplayer` for the proposed
source comparison and staged migration plan after reviewing SistrumKotlin. A later
question asks whether app-owned C++ and FFmpeg can eventually be removed.
Binding decisions: Flutter UI is retained; Android/arm64 is the target; this batch
compares and plans only. The existing migration guide's recorded D1–D6/E01–E12 are
identified in the plan, including policies that must be reconciled before execution.

## User scenarios

### Story 1: Assess reusable playback components (Priority: P1)

The owner can distinguish implemented source-project capabilities, current target
behavior, missing integrations and unverified claims.

Why this priority: existing Kotlin implementation and owner-reported device use
change the feasibility estimate, but do not establish complete Flutter-app parity.
Independent test: inspect the feature matrix and confirm its evidence paths against
both pinned source revisions.

Acceptance:
1. Given the current target and reference revisions, When the owner reads the
   comparison, Then every retained playback area has a disposition and verification
   requirement, including unsupported or unverified cases.
2. Given source-project device experience, When evidence is summarized, Then it is
   acknowledged separately from tests of a future target integration.

### Story 2: Choose a staged migration without accidental feature removal (Priority: P1)

The owner can review ordered batches and determine what must be proven before a
consumer switches or an implementation/dependency is deleted.

Why this priority: replacing an engine must not silently replace beat-matched AutoMix,
Cast or USB behavior with superficially similar features.
Independent test: trace every proposed removal to its acceptance gate and retained
feature coverage.

Acceptance:
1. Given the roadmap, When a future batch is considered, Then its prerequisites,
   owner of state and acceptance/removal condition are stated.
2. Given current uses of FFmpeg and native output, When removal is considered,
   Then playback-only success is not presented as sufficient deletion evidence.

## Edge cases

- A selected queue item beyond the reference's 1,000-item cap, or duplicate IDs before
  the selected index, must not change which song plays after adaptation.
- Revoked SAF access, missing files, unknown duration and non-seekable input require
  explicit future acceptance cases, not an assumption that every source is a path.
- Flutter detach/reconnect, screen-off playback, stale events, focus loss and route
  changes must be included in the future service acceptance.
- A PCM DSD decoder, ordinary crossfade or system output switcher must not be labeled
  native DSD/DoP, beat-matched AutoMix or full Google Cast equivalence.

## Requirements

- FR-001: The planning artifact MUST identify both repositories and exact revisions.
- FR-002: The artifact MUST cover transport, queues, gapless, AutoMix, gain/EQ,
  format/decoder coverage, USB/DSD/HiRes, Cast, background/session/Auto/widgets,
  persistence, SAF, CUE, haptics/preview and independent online-source work.
- FR-003: The artifact MUST distinguish source evidence, owner-reported experience,
  newly executed checks and pending host/device verification.
- FR-004: The roadmap MUST assign final playback ownership to Kotlin with Flutter as
  client, while specifying that an intermediate stage has only one live owner.
- FR-005: The roadmap MUST state separate FFmpeg, app-owned C++ and Rust-audio removal
  gates, with no deletion based on source presence or language preference alone.
- FR-006: This batch MUST NOT modify/import production player code, dependencies,
  minimum SDK, licences, preferences, database schemas or runtime selection.
- FR-007: Historical policy decisions and incomplete prerequisites MUST remain
  visible rather than silently treated as newly approved implementation decisions.

## Success criteria

- SC-001: One readable comparison/roadmap covers every FR-002 area with evidence and
  disposition, and links to the formal planning record.
- SC-002: The change diff contains documentation and planning records only; target
  production trees and the reference checkout remain unchanged.
- SC-003: The requested branch exists with reviewable commits and no base-branch merge.

## Out of scope

Actual engine/decoder imports, bridge implementation, removing any native dependency,
changing output policy, a backend rewrite, source-updater activation, new UI or APKs.

## Assumptions

- Branch from current `extension-system` HEAD to preserve the completed internal-source
  work; no cherry-pick, merge or remote history rewrite.
- The requested first deliverable is the comparison and plan proposed immediately
  before the branch request, not implementation of the entire migration.
- Future source imports retain actual licence/provenance requirements.

## Clarifications

- Owner: Kotlin code was tried on their phone; acknowledge that evidence without
  inventing its device/scenario coverage or equating it with this app's validation.
- Owner: asks whether C++/FFmpeg can retire; document it as a possible end state with
  per-consumer gates, not permission for immediate removal.
