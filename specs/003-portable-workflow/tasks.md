# M003 tasks

- [x] M003-T001 Consolidate workflow tools and update canonical paths

- [ ] M003-T002 Install portable workflow resources and preserve existing history

- [ ] M003-T003 [FINAL] Verify portable setup and cumulative changes

All tasks refresh the map first, then Ponytail/check/review/fix with at most three
review results, and helper-driven completion/history in the same task commit.

M003-T001: move helpers/analysis/provenance and active path references to workflow/;
checks full helper/analysis suites, actual status/doctor/template/CI paths, no app edits.
M003-T002: bootstrap + default assets + comprehensive README and preservation tests;
checks isolated transfer, core setup and existing data safety. Depends on T001.
M003-T003: cumulative review, full feasible checks and resolve final findings in one
commit. Depends on both tasks; no APK/app/device checks or global settings required.
