# Plan {{ID}}: {{TITLE}}

<!-- How. Written for a reviewer who has not seen the conversation: everything it needs is here or linked.
     Facts about the current code cite file:line. Write "unchanged" or "none" rather than deleting a row. -->

## Summary

[FILL: the approach in a few sentences]

## Current system

[FILL: how it works today, with file:line; what the change touches and who calls it]

## Design

- Ownership and dependency direction: [FILL]
- Contracts across Dart, Kotlin and Rust (methods, fields, units, errors): [FILL]
- State, threads, lifecycle and cancellation: [FILL]
- Failure: what the user sees, what survives a failed write: [FILL]
- Data compatibility (song IDs, schema, backups, preference keys): [FILL]
- Removal: what goes and the proof nothing still uses it: [FILL]

## Decisions

- PD-1: [FILL: decision]. Rationale: [FILL]. Alternatives considered: [FILL].

## Constitution check

- [ ] I. Owner decisions and removed features respected
- [ ] II. Every step has a check; device-only behaviour listed as pending
- [ ] III. Root cause stated; smallest complete change; nothing on the never-cut list removed
- [ ] IV. Regression, characterization or differential tests planned where behaviour changes
- [ ] V. Failures typed and distinguishable
- [ ] VI. Boundary contracts tested on both sides; one owner per state
- [ ] VII. Originals survive failure; IDs, schema, backups and keys compatible
- [ ] VIII. Independent review planned at the required level
- [ ] IX. No speculative layers; deviations recorded below
- [ ] X. Commit plan; no push or APK without the owner

## Complexity tracking

| Deviation | Why needed | Simpler option rejected because |
|---|---|---|

## Verification plan

- Host checks: [FILL: work.py check profiles and the tests that cover each requirement]
- Device checks for the owner: [FILL or "none"]

## Open choices for the owner

[FILL: options with mechanism, trade-offs and failure conditions, unranked; or "none"]
