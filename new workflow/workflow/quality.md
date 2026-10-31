# Review method, without scores

Before implementation, trace entry points, data flow, consumers and guards. During implementation, make coherent changes and verify their effects. After implementation, review the surrounding system as well as the diff. Whole-subsystem audits are explicit or justified by evidence; never scan everything for a label change.

For spec-driven work, apply `workflow/spec-driven.md`: check requirements/design/tasks for contradictions and missing coverage before execution, then compare delivered behavior and evidence against intent. Requirements-quality approval is not code verification. Stable requirement IDs support traceability, not scores.

## Review lenses

1. Responsibility/cohesion: does one unit have unrelated reasons to change? Would extraction improve ownership rather than only file length?
2. Dependency direction: cycles, UI imports in data/engine code, domain code reaching transport details.
3. API coherence: names, types, units, nullability, error behavior and resource ownership mean the same thing across consumers.
4. Initialization: hidden side effects, duplicated startup, order assumptions, partial failure and recovery.
5. Data integrity: identity, schemas, transactions, publication, compatibility, failure preserving originals.
6. Concurrency/lifecycle: cancellation, stale results, synchronization, resource disposal, service versus screen lifetime.
7. Error semantics: unsupported/not-found/failure/cancelled are distinguishable; errors reach actionable UI or diagnostics.
8. Test quality: meaningful failure cases and boundary tests, not assertions that repeat implementation; mocks cannot prove native behavior.
9. Performance: bounded queues/buffers/work, main-thread I/O, redundant calls, allocation/copy pressure; measure before claiming optimization.
10. Simplicity and consistency: reuse healthy patterns, remove obsolete paths, resist speculative features and forward-only wrappers.

Dart part files form one library. Private splits do not reduce public surface or fix dependency direction. No universal line limit or score goal. Existing reference code may carry bugs; verify it against requirements.

## Finding threshold

A confirmed finding needs file:line, a concrete trigger, affected callers, existing guards inspected, consequence and a defensible fix. Confidence is separate from severity. Use CONFIRMED, NEEDS_VERIFICATION or REJECTED_WITH_EVIDENCE. Record potential high-impact issues even if reproduction requires hardware; do not report them as observed failures.

Priorities: P1 data loss/security/major unavailable function; P2 functional correctness/lifecycle; P3 maintainability or measured cost. No style nits. Deduplicate by root cause. An empty findings list is valid. Do not close a finding because code moved or a scanner stopped seeing it.

## Finish and learning

Completion requires the goal, relevant checks, review outcomes and current evidence; a green command alone is not enough. Use COMPLETE, IMPLEMENTED_PENDING_VERIFICATION or BLOCKED. Repeated verified mistakes become a structural/type rule, lint or behavioral regression test when feasible. Judgment-only lessons belong in a short decision. Avoid accumulating rules for isolated guesses.

After the same failed approach twice, inspect the shared assumption and change the investigation. Allow at most four review/fix rounds for a scoped issue; unresolved disagreement is reported, not accepted as approval. Never drop tests, hide failures or broaden exclusions to satisfy the workflow.
