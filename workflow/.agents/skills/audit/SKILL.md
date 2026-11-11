---
name: audit
description: "Cleanup audit of a named scope. Kinds: code (dead, simpler, better written), tests (redundant or empty tests), gaps (code without tests), leaks (unreleased resources), security (secrets, vulnerable dependencies). code, tests and gaps run automatically in a plan's [AUDIT] task before the final review; leaks and security run only when the owner asks."
---

# Audit

```sh
python3 workflow/scripts/work/work.py audit --kind code|tests|gaps|leaks|security  (default: code)
        --lang dart|rust|kotlin|cpp     # one language (repeatable)
        --path lib/services/cast        # a file or directory (repeatable)
        --change NNN                    # files a change touched
        --base COMMIT                   # files changed since a commit
```

Filters combine; one of them is required, because the whole repository is never audited in one run. The
command only reads. It writes `.work/audit/<scope>-<kind>.md` (local, never committed). Vendored and generated
code (`protected` in `workflow/work/audit.json`) is never audited.

## When it runs

- `[AUDIT]` task: every plan's tasks.md has one directly before `[FINAL]`. `task start` writes the code, tests
  and gaps reports for the files the change touched. The owner may delete the line to skip the audit.
- On request: any kind, any scope. `leaks` and `security` run only this way. They are never part of a plan.

## Three levels of evidence

1. Proven: the language tool reports it inside the scope (`Proven by a tool` in the report). Fix it.
2. Lead: a mechanical hint from the command (`Leads to verify`). Not proof.
3. Candidate: a finding from a fresh read-only `workflow/.agents/reviewers/code-auditor.md` given the report
   path. If no fresh reviewer can be started, label the result a self-audit.

Leads and candidates are verified before anything changes. Verified means you confirmed, by reading the code
and by the check named below, that it is a real problem. Fix what is verified. Leave what is not, and record it
with the reason. Do not wait for the owner on either; the owner reads the outcome in the report.

A tool that is missing or a language with no tool is a coverage gap: report it, never "nothing found".

## Verifying and fixing, per kind

code
- Dead: read both sides of every boundary that could reach it (method channels, uniffi/JNI, the manifest,
  Gradle, reflection, config strings). Remove it and run the checks of every domain it touched. A red check
  means it was not dead: restore it and record it as kept. Compilation is the proof; a missing text match is not.
- Simpler or better written: only with a named reason (see the auditor's patterns), identical behaviour, and a
  test that covers the code and passes before and after. No covering test: write it first (gaps rules) or
  leave the code alone. Style and taste are not reasons.

tests
- Same body: merge only when the setup and the code path are also the same. Keep the stronger test.
- No assertion: decide what failure the test can detect. None: give it the assertion it was meant to have, or
  remove it if another test already covers that behaviour.
- Never remove a test that pins a past bug, a data format, a backup, a migration or a bridge contract.
- After removing or merging, the remaining tests must still fail when the behaviour is broken: break the line
  briefly, see the test fail, restore it. The aim is confidence, not a smaller count.

gaps
- A file no test names may be covered through a higher-level test. Check before writing.
- Write tests for behaviour, highest risk first (`high_risk` in checks.json): failure paths, boundaries,
  lifecycle. Not for a percentage. Use the smallest test level that proves the behaviour.
- Before adding a test, answer: what behaviour it protects, what regression makes it fail, why no existing test
  catches that. If it needs a change in production code only tests would use, do not add it; record the gap.
- Every new test is seen failing once: break the covered line, see it fail, restore it.
- Coverage data: produce it with the command the report names, for the test folders of the scope only.

leaks (on request)
- Proven (`cancel_subscriptions`, `close_sinks`): add the missing release. Candidates: confirm the owner object
  really outlives the resource before changing anything.

security (on request)
- Report only. Never fix automatically: a security fix changes behaviour and goes through a normal task.
- Confirm a possible secret is real before reporting it (a key name is not a secret). Never print a secret's
  value. A real secret must be rotated at its source by the owner; deleting it from the code is not enough.
- For a vulnerable dependency, say whether the affected code path is used. The scan covers the working tree and
  `pubspec.lock`/`Cargo.lock`; Git history and Gradle dependencies are not covered.

## Applying

Code changes go through the task loop: inside the active `[AUDIT]` task, or, on request outside a change, a
`new "Audit <scope>" --size small` change. Group edits by kind in log.md so a regression can be traced. Never
touch protected paths. Never widen the scope while applying. Then the normal loop: `task check`, independent
code review of the edits, one commit. An audit that changes nothing still completes with its records.

## Keep list

Something verified as not a problem that the tool keeps reporting goes into `keep` in
`workflow/work/audit.json` with the reason (`{"path": glob, "reason": text, optional "code", optional
"contains"}`), so later audits skip it.

## Report to the owner

Scope and file counts per kind; what was fixed (count, kinds, checks that passed after); what was verified as
not a problem and left, one line each; coverage gaps; what was not verified.
