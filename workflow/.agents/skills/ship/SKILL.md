---
name: ship
description: "Finishing work: final checks on the final tree, drift between spec, plan and code, lessons turned into checks, commits with explicit paths, and the report. Push, APK builds and releases only when the owner asks in the current conversation."
---

# Finish and publish

Execution finishes through the last [FINAL] task, not separate build/review/ship gates.

- Confirm all implementation/TOR tasks have actual verified commits. Final review/checks cover
  the cumulative change and declared assurance/device requirements. Fix final findings in the
  final task and respect its three-review limit.
- Reuse passing evidence when its code/requirement identity is unchanged. Do not rerun an
  entire suite merely because progress/log/report files changed. Fingerprints stay internal;
  no manual fresh step is required.
- Planning artifacts are ONE planning commit. Each reviewed task is ONE commit containing
  code, tests, fixes and records. Never split a task into code and records commits; never
  create empty Git commits or rewrite unrelated history. Stage explicit paths.
- task complete prepares records; ordinary Git makes the commit; task status verifies it.
  If Git fails, preserve edits and retry/reconcile. Never mark waiting_commit as done.
- Report behavior changed, checks/counts, unavailable/skipped verification, commits and
  remaining limitations. Do not claim device testing without actual evidence.
- Push, APK and releases require the owner's request. Never force-push or skip hooks.
  Flutter tests and APK builds never overlap. Current request may explicitly prohibit APK.

Legacy records/diagnostic commands remain readable but are not new execution steps.
