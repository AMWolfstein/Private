# M002 — Workflow preparation and task identity

Restore status/doctor/setup for the current portable Spec Kit/Ponytail/analysis
setup, without restoring legacy fingerprints or an execution engine. Provision
only local analysis dependencies; surface missing application toolchains honestly.

Every mission has a unique M###; feature tasks use M###-T###. Standalone TOR###
and mission M###-TOR### share one monotonically allocated TOR number pool. Reserved
numbers are never reused. Prevent same-checkout races and detect invalid/manual
IDs or conflicting/reassigned reservations through validation and GitHub checks.
Disconnected clones require reconciliation; no false distributed uniqueness claim.

Add root TASK_HISTORY.md containing only completed full task IDs and names.
Maintain detailed evidence in task records. Import the existing completed native
feature as M001 and preserve the existing standalone TOR001. This implementation
is M002. No fabricated history for unrecorded prior changes.

All commands work from ordinary agent-independent repository instructions. No
application changes, global hooks, APKs or automatic merge/force-push. Keep map-first,
three reviews maximum and one planning commit/one commit per task.
