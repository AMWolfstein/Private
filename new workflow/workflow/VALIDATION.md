# Starter validation

Date: 2026-10-31. Scope: this portable package, not application code.

- Python standard-library test suite: 21 cases covering nonzero exits, missing tools/prerequisites, unconfigured suites, timeout, content/deletion/untracked-input fingerprints, source mutation during verification, stale/failed evidence rejection, Arabic advisory routing and relocation to a directory containing spaces. Spec Kit integration adds feature/port skill selection, read-only review of a proposed port, lightweight clear-fix routing and rejection of missing spec skill/template.
- Package structure/configuration validation and bridge execution-plan inspection.
- Migration/bridge routing example selects migration plus Flutter/Android/bridge/playback concerns. This is routing evidence, not an autonomous model benchmark.
- Documentation self-review: target versus current state, D6 precedence, new-repository comparison strategy, explicit pending device gates, no inherited application PASS claims.

The first test invocation used an incorrect relative creation path and ran no tests; it was corrected. The successful test run is the evidence, not that initial invocation.

For the Spec Kit integration, the new routing/validation tests were run against the old runner first and failed as expected; after integration the 21-case suite passed. These tests prove deterministic selection/package checks, not semantic requirement coverage or autonomous reviewer quality.

The independent reviewer for this integration could not start because the agent service reported a usage limit. No independent verdict was produced. Self-review covered routing intent, spec/design/task consistency, authority, upstream adaptations and honest completion gates; it does not replace independent review. Integration status: implemented and host-tested, independent review pending under `.agents/skills/sistrum-workflow/SKILL.md` step 7.

Not validated: a real new Flutter/Gradle application, actual Media3 port, app contract/parity tests, on-device audio/performance, or fresh-agent end-to-end workflow effectiveness. Independent review of this starter remains pending. The package's successful command profile cannot close those gaps.

## Pilot acceptance before broad adoption

1. Small UI task: agent uses existing component and runs relevant checks without a needless design/swarm. Confirm the selected scope manually.
2. Bridge task: introduce a mismatched field/unit and stale callback in an isolated fixture project; app contract/lifecycle tests and independent review must catch each. Record misses and false positives; restore the fixture afterward.
3. Port task: compare one bounded decoder/data operation against reference inputs, including failure and cancellation. Verify intentional differences are recorded and obsolete paths are removed only after acceptance.

These pilots are required future application exercises, not tests already performed by this package. Extend enforcement from actual repeated failures, not speculative rules.
