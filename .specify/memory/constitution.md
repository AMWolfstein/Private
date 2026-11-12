# Mornye Constitution

## I. Preserve behavior and scope

Current owner instructions define the goal. Preserve observable behavior outside
that scope, particularly audio playback, decoder/fallback selection, rendering,
stored data and native contracts. Never remove uncertain dynamic/native APIs on
the basis of missing static references. Keep generated/vendor code protected.

## II. Plan substantial work

Use GitHub Spec Kit spec → plan → tasks for substantial/high-risk changes or when
requested. Small isolated low-risk edits may take the direct path. Planning-only
requests stop at the plan. Completed planning artifacts form one commit.

## III. One task, one reviewed commit

Follow [project policy](../project-policy.md): T000 map refresh, T001 implementation,
map refresh before subsequent tasks, sequential implementation/check/review/fix
loops and one commit after each task passes. After three unsuccessful review
rounds stop and report. Extras are TOR###. The final task reviews the cumulative
change and contains all its fixes in one commit.

## IV. Honest verification

Use meaningful checks for the affected languages and boundaries. Distinguish
baseline failures from regressions, unsupported coverage from clean results,
inferred links from verified references, and self-review from independent review.
No device testing, benchmark benefit or cross-ABI success without actual evidence.
Do not build APKs unless requested. No new app dependencies solely for analysis.

## V. Simple tooling and Git safety

Keep CodeGraph/adapters/Serena and the combined audit independent. No legacy
work.py/task-state/fingerprint gates. Preserve unrelated changes. No speculative
cleanup, automatic merging or history rewriting. Publishing follows authorization.

## Governance

Owner instructions override this constitution; it and project-policy.md override
conflicting upstream examples, parallel markers and converge defaults. Amend
policy only for an actual agreed change, not to evade a failed check/review.

**Version**: 1.0.0 | **Ratified**: 2026-11-12 | **Last amended**: 2026-11-12
