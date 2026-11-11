# Tasks {{ID}}: {{TITLE}}

<!-- Execute in order. task start refreshes the map and context for each task.
     The last pending task always has [FINAL].
     Only mark [x] after checks, clean independent review and its one commit.
     Owner requests become TOR### before the next pending implementation task.
     Never rewrite completed tasks. Maximum three reviews per owner-authorized cycle.
     The [AUDIT] task stays directly before [FINAL]; delete its line only if the owner skips the audit.
     The [APK] task is the very last, after [FINAL]: a local verification build, never published. -->

- [ ] T001 [FILL: complete unit of implementation, files and FR-###] — check: [FILL: check IDs or auto]
- [ ] T002 [AUDIT] Audit the files this change touched: dead or simpler code, redundant tests, missing tests — check: auto
- [ ] T003 [FINAL] Review cumulative implementation and all completed tasks — check: auto
- [ ] T004 [APK] Build the arm64 release APK from the reviewed code — check: apk
