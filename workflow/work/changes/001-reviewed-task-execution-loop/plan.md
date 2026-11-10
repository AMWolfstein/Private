# Reviewed task execution loop design

## Current system
workflow/scripts/work/work.py:29 defines project phases; :279 lint_change gates artifacts and :388 record_round stores whole-project reviews. :50 fingerprints the tree excluding process records; :507 runs real checks. Existing skills require build/review/ship transitions and code/record commit separation. These are superseded for new execution records by the owner's approved task loop.

## Design
- New worktasks.py owns schema-2 execution ledgers; work.py remains the CLI/check runner. New records use spec/plan/tasks/done visible phases; legacy records/commands remain readable through compatibility branches, not required for new work.
- Planning stays unchanged except its artifacts are committed together. A planning commit records its parent rather than its own unknown hash. Tasks begin only after that checkpoint is actually committed. Small changes use minimal tasks/state/log records and start in execution without planning.
- tasks.md IDs are T000, T001... and TOR###. Final review is a normal T### row with [FINAL]. T000 is first. Pending final review is last. Later owner requests enter before the next pending task; a request after a completed project appends a fresh final task rather than rewriting completed history.
- Task states: pending -> active/fixing -> reviewed -> done; third dirty result -> blocked. Never allow a fourth review, a blocked task commit, starting another task while one is active/uncommitted, or completed-task edits. Third clean result is allowed. A block needs explicit owner intervention, never automatic counter resets.
- task start refreshes the map and emits context, captures HEAD, protected pre-existing untracked files and task definition. A stale/unavailable map cannot count as a successful task start. Task check selects checks against the task's starting commit; final check uses the change's original base. Explicit additional check IDs are supported.
- task packet refreshes final map context and verifies fresh real runner evidence; task review records independent-reviewer verdicts against packet code/plan fingerprints. A clean review requires no unresolved scoped findings. Reports/progress do not affect code fingerprints; plan/task requirements remain part of review identity. Map/context facts remain leads, not reachability proof.
- task commit revalidates checks, review fingerprint and unchanged HEAD. It stages explicit task-changed paths plus its own completion records, creates one Git commit and only then permits the next task. Completion metadata is written before commit and rolled back if commit fails. No post-commit record-only commit or history rewrite. Protect unrelated staged/pre-existing untracked content; do not stash or delete it automatically.
- Final review covers cumulative diff from original base plus all task outcomes and declared assurance/device requirements. Source fixes and task records are one commit. Real evidence-record changes are legitimate; no --allow-empty commits.
- Preserve native check runner, timeouts, logs and map extraction. check defaults to auto using active-task baseline; --full explicitly runs every configured check. No selected checks yields NO_CHANGES, not a fabricated PASS or overwritten latest evidence.
- Task commands are agent internals; owner supplies requests normally. Documentation/reviewer prompts/templates must describe this same model and small/large classification. No automatic push/APK.

## Decisions
- PD-1: Separate new task mechanics from legacy gates to preserve history/tests and avoid changing app source.
- PD-2: Keep code fingerprints internal and add reports/ to excluded output folders; no broad exclusion of source/config file types.
- PD-3: Retain independent review judgments and structural enforcement; the tool cannot prove semantic correctness or reviewer identity.

## Constitution check
- [x] I. Owner-approved process changes supersede prior execution rules.
- [x] II. Runner evidence is mandatory and tied to code.
- [x] III. Scope limited to workflow tooling/docs.
- [x] IV. Meaningful behavioral and Git integration tests.
- [x] V. Explicit no-changes, blocked and incomplete statuses.
- [x] VI. One active task/owner; no app bridge changes.
- [x] VII. Preserve unrelated files, legacy records and Git history.
- [x] VIII. Independent design/code reviews.
- [x] IX. Three task review rounds, no repeated completed work.
- [x] X. One planning commit and one per reviewed task; no push/APK.

## Verification plan
Throwaway Git repository task-loop tests; existing workflow suite with real parser/graph integration; final workflow check over the complete workflow diff. No Flutter/Android/Rust app checks needed for unchanged app code. No device tests apply.

## Complexity tracking
Legacy compatibility is retained only for existing records and regression coverage. New records cannot enter the old build/review/ship sequence.

## Open choices
None: owner approved this process and implementation.

## Enforcement details clarified by design review
- Task start requires no pre-existing tracked source/config/test modifications, staged or unstaged. Existing untracked files in configured domains also block start. Unmapped pre-existing untracked files are captured by content/mode and protected: edits/deletion block task completion, and their paths are never staged. Progress records may be dirty only within this change; unrelated staged records also block commit.
- Every task check stores its code fingerprint, task/plan/assurance requirement identity and exact selected check IDs before execution; it compares code and requirement identity after execution. Packet/review/commit recompute required checks and reject mismatched identities. A changed task check declaration or assurance requirement invalidates the task's check record even when code is unchanged. Existing global runner evidence alone is not sufficient.
- NO_CHANGES is only a truthful check-selection result, never runner PASS. When the required set is empty, task evidence is explicitly NOT_REQUIRED, tied to current task requirements/code/map, and independent review remains mandatory. T000 additionally requires a current map result. Final review still uses cumulative selection; an empty final-task diff cannot hide earlier changed code. Additional observable/manual acceptance remains the reviewer's responsibility; the tool does not pretend to prove human observations.
- After three dirty reviews the task remains blocked with its full review history. Only an explicit task resume --owner-instruction "literal owner instruction" opens a new review cycle; it preserves all old rounds and records the instruction. This command must never be invoked automatically. The limit is three per owner-authorized cycle; there is no fourth automatic review or counter deletion. Pausing/abandoning is also allowed without committing unfinished work, but cannot silently advance the queue.
- All task-mutating operations take one repository-local advisory operation lock, separate from the map lock. A commit uses a durable ignored journal: parent HEAD/branch, before-images of its own records/index, transaction nonce, and expected staged Git tree. Completion metadata contains that nonce and parent; before allowing later work, recovery proves it exists in the expected immediate child commit. A crash before Git commit restores only owned records/index when safe, preserving source edits. A crash after successful commit reconciles the committed tree and never rolls it back. Unexpected HEAD/index changes block recovery instead of discarding work. Read-only status must report an unresolved commit transaction rather than claim done.
- The ordinary task definition hash includes its own declaration plus spec/plan/assurance; final review includes the complete task inventory. Adding a queued TOR does not pretend that another task's source was reviewed; edits to completed task declarations are rejected. No empty Git commits are allowed; meaningful completion records are valid commit contents.
