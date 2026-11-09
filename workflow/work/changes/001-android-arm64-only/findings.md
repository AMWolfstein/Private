# Findings 001-android-arm64-only

<!-- One "### F-NNN" section per finding, from design and code review rounds.
     Severity: blocker | major | nit
     Status: open | fixed | contested | escalated | declined | false_positive | wontfix
     Every status except open needs an Evidence line: commit, test, file:line or command result.
     A finding that a later round does not repeat is still open until its Evidence says why.

     Example (indented so the tool does not read it):

     ### F-001 [code r1, code-reviewer] A cancelled scan still publishes rows
     - Severity: major
     - Status: fixed
     - Where: lib/services/library/scan/scanner.dart:120
     - Trigger: cancel during the second batch
     - Resolution: fix
     - Evidence: test/library/scan/cancel_test.dart "cancel stops publishing", commit abc1234
-->

### F-001 [design r1, goldfish-reader+design-critic] Round 1 findings (13) answered in plan v2
- Severity: major
- Status: fixed
- Where: plan.md
- Resolution: fix
- Evidence: plan.md v2 header ("v2 answers the design review (13 findings)"), commit 824edbf, now part of a8301fc. The individual round 1 findings were not copied into this file at the time and the reviewer reports were not kept; this entry records that gap.

### F-002 [design r2, goldfish-reader] Spec Story 3 Acceptance 2 still requires a Link migration
- Severity: major
- Status: fixed
- Where: spec.md Story 3
- Resolution: fix
- Evidence: spec.md Story 3 Acceptance 2 now states first install, no Link table created

### F-003 [design r2, goldfish-reader] SC-003 forbids skipped or removed tests that the plan has
- Severity: major
- Status: fixed
- Where: spec.md SC-003
- Resolution: fix
- Evidence: spec.md SC-003 rewritten: kept-feature tests pass or are skipped with a recorded reason; removals only with removed features

### F-004 [design r2, goldfish-reader] SC-002 exceptions and search command missing
- Severity: major
- Status: fixed
- Where: spec.md SC-002, plan.md Verification plan
- Resolution: fix
- Evidence: plan.md Verification plan gives the rg command and the allowed exceptions; spec.md SC-002 points to it

### F-005 [design r2, goldfish-reader] SC-001 wants an APK named for arm64-v8a, the build makes app-release.apk
- Severity: major
- Status: fixed
- Where: spec.md SC-001, Story 1
- Resolution: fix
- Evidence: spec.md SC-001 and Story 1: one APK containing arm64-v8a libraries only

### F-006 [design r2, goldfish-reader] FR-008, Story 3, Edge cases, Input and Out of scope not updated for v3
- Severity: major
- Status: fixed
- Where: spec.md
- Resolution: fix
- Evidence: spec.md FR-007, FR-008, FR-010, Story 3, Edge cases, Input, Out of scope and Assumptions rewritten for v3

### F-007 [design r2, goldfish-reader] Plan Current system still calls the Discord code exceptions
- Severity: major
- Status: fixed
- Where: plan.md Current system
- Resolution: fix
- Evidence: plan.md Discord bullet marked as base state removed by PD-3

### F-008 [design r2, goldfish-reader] assurance.json bridge reason ignores the path-key contract and SQL view
- Severity: major
- Status: fixed
- Where: assurance.json, plan.md Design
- Resolution: fix
- Evidence: assurance.json bridge reason names the path-key fixture tests; plan.md Contracts names path_match_keys.dart, path_keys.rs and the library_schema.dart view clause

### F-009 [design r2, goldfish-reader] Added scope (Windows path identity, remnants, dead code) has no inventory
- Severity: major
- Status: fixed
- Where: plan.md PD-9, PD-10
- Resolution: fix
- Evidence: plan.md Added scope inventory (v3) lists the removed files and symbols

### F-010 [design r2, goldfish-reader] Constitution VIII claimed before the rounds exist; code landed before design review
- Severity: major
- Status: fixed
- Where: plan.md Constitution check
- Resolution: fix
- Evidence: plan.md VIII reworded as the requirement: two clean design rounds, then two clean code rounds over the diff from 365dcae

### F-011 [design r2, goldfish-reader] Clarifications v3 does not supersede the split in three
- Severity: major
- Status: fixed
- Where: spec.md Clarifications
- Resolution: fix
- Evidence: spec.md Clarifications v3 states it supersedes the split in three; the old answer is marked superseded

### F-012 [design r2, goldfish-reader] Task IDs and the restored update test are not explained; FR-009 message has no check
- Severity: nit
- Status: fixed
- Where: plan.md
- Resolution: fix
- Evidence: plan.md Characterization names tasks.md and where the test came from; plan.md Design names update_dialog.dart for the message

### F-013 [design r2, goldfish-reader] Build sentence joins two facts
- Severity: nit
- Status: fixed
- Where: plan.md Design Build
- Resolution: fix
- Evidence: plan.md Design splits the ABI split and flutter_git_commit.sh into two bullets

### F-014 [design r2, design-critic] Spec requirements still state the decisions v3 replaced
- Severity: major
- Status: fixed
- Where: spec.md, plan.md
- Resolution: fix
- Evidence: spec.md FR-007, FR-008, FR-010 to FR-014, SC-001 to SC-004, Story 3, Edge cases, Out of scope and Clarifications rewritten for v3; plan.md Discord line updated

### F-015 [design r2, design-critic] Skips without reasons, no baseline, untested header edit, loosened cover cache test
- Severity: major
- Status: fixed
- Where: test/
- Resolution: fix
- Evidence: Pre-work baseline at e02860c (log.md): the 3 album header, 2 rewind and material backdrop blur tests fail there too; each of the 7 skips now has a reason; the semantics test is unskipped (it guards the project's SDK patch and passes 3/3 on the patched SDK); test/cover_cache_info_repository_test.dart again asserts the saved index after close; new album header test covers title, cover, action size and collapsing; commit 4fac672

### F-016 [design r2, design-critic] Rust check planned as a pass while a cover test was known to fail
- Severity: major
- Status: open
- Where: plan.md Verification plan, SC-004
- Resolution: fix
- Evidence: Pending the check auto run on 4fac672; the cover test was fixed by upstream commit 4831b065 during the work

### F-017 [design r2, design-critic] Review gate claimed early, round 1 findings missing, base not an ancestor of HEAD
- Severity: major
- Status: fixed
- Where: plan.md, findings.md, state.json
- Resolution: fix
- Evidence: plan.md VIII reworded; F-001 records the round 1 gap; state.json base set to 365dcae, an ancestor of HEAD

### F-018 [design r2, design-critic] Update check reads the device ABI it cannot need and can wrongly report no compatible APK
- Severity: major
- Status: fixed
- Where: lib/services/update_checker.dart, FR-009
- Resolution: fix
- Evidence: Device ABI read removed; the arm64 APK is offered whenever the release has one; regression test "the arm64 APK is offered without reading the device ABIs" failed before and passes after; spec.md FR-009 updated; commit 4fac672

### F-019 [design r2, design-critic] rust_backend READMEs still name armeabi-v7a
- Severity: nit
- Status: fixed
- Where: rust_backend/README.md, rust_backend/vendor/README.md
- Resolution: fix
- Evidence: Both READMEs now describe arm64-v8a only
