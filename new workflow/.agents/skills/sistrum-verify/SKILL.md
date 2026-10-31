---
name: sistrum-verify
description: "Use automatically before claiming completion; execute appropriate checks, assess coverage and preserve current evidence and limitations."
---

# Verify and retain lessons

1. Choose profiles using actual risk and consumers, not extensions alone. Read `workflow/verification.json`; confirm each command's real scope. Run `plan` first on a newly configured repository. Missing tools/tasks or empty commands are blockers, not skips.
2. Run covering unit/contract/lifecycle tests, relevant static analysis and batch-level suites. Flutter checks run serially with Android build operations. No APK packaging is implicit. `run` logs exits and fingerprints, but does not know whether a test suite exercises the claimed behavior.
3. Review failures and check counts. A zero-test suite cannot establish behavior. Device compilation is not device execution; a mocked channel is not a Kotlin/JNI test. Do not substitute the workflow's own unit tests for app tests.
4. Use `fresh` on saved command evidence. It hashes file content and paths, including untracked inputs, with explicit exclusions documented in the runner. If evidence is stale, identify relevant changes and rerun appropriate checks; never relabel old results as fresh. Excluded build output still needs artifact/build identity for device evidence.
5. Record build mode/commit, hardware, Android version, ABI, sample counts and actual results for device/audio/performance checks. No invented latency, allocation, power or bit-perfect claims.
6. Complete only when task criteria, required independent review and checks pass on final relevant code. Otherwise report IMPLEMENTED_PENDING_VERIFICATION or BLOCKED and the exact missing evidence.
7. Repeated verified failures become a structural/type fix, lint or regression test. Prove a new enforcement fails for a representative bad case and passes for the fix. Keep judgment-only rules short; do not grow a rulebook from every isolated problem.
