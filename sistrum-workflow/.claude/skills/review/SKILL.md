---
name: review
description: "Independent code review in a fresh, read-only context, and owner-requested audits. Mechanical checks first, then a review packet for a reviewer that never sees the conversation; every finding is fixed, contested with evidence, escalated or declined, and the final code must pass a clean round."
---

# Review

## When

- Required before shipping a feature or architecture change.
- For a fix that touches a `high_risk` path in `work/checks.json`.
- When the owner asks for a review or audit: read-only, findings only, unless the owner asks for fixes.

## 1. Mechanical first

`python3 scripts/work/work.py check auto` and `python3 scripts/work/work.py lint <NNN>`. Tool output is
evidence, kept separate from the reviewers' judgment. Fix mechanical failures before asking a reviewer.

## 2. Convergence

Check every `[x]` task and every FR against the code, not against the tick: a completion mark is not evidence.
A gap becomes a new task under "## Convergence" in `tasks.md` with the next ID (missing, partial, contradicts the
spec, or unrequested code). Never rewrite finished tasks.

## 3. Fresh-context review

1. `python3 scripts/work/work.py packet --base <base> --change <NNN> --out .work/review/<NNN>-code-r<N>.md`.
   The base is the commit before the change (`HEAD` for uncommitted work). For a fix without a change record,
   use `--goal` with a short file stating the bug and the intended behaviour.
2. Start `code-reviewer` with only: "Review the packet at <path>." No conversation, no opinion, no target.
   When the change crosses Dart, Kotlin and Rust or touches stored data, start a second `code-reviewer` with one
   extra line naming that focus. Never more than two.
3. A reviewer that fails or times out has not run. Retry once; it is never a clean round.

## 4. Resolve every finding

Record each as `### F-NNN [code rN, reviewer] title` in `findings.md`, with Severity (blocker, major, nit) and
Status, then:
- fix it, with a regression test when it is a behaviour bug, and Evidence naming the test and commit;
- contest it only with evidence the reviewer could check;
- escalate what needs the owner's knowledge or decision;
- decline nits, or record wontfix or false_positive with the reason as Evidence.
A finding that a later round does not repeat stays open until its Evidence says why it is resolved.

For an audit the owner asked for, stop here and present the findings by severity.

## 5. Rounds

`python3 scripts/work/work.py round <NNN> code clean|dirty --reviewer code-reviewer`. After fixes, the next packet
covers the changed code and the open findings, not the whole project again. At most 4 rounds; then list what is
open and ask the owner. `work.py advance <NNN> ship` requires the last round to be clean on the current tree,
so any edit after a clean round needs one more round.

## Review coverage

Use `work/guides/quality.md` for cohesion, cross-module dependencies, API coherence and initialization, as well as safety and correctness. For bridge/data changes use `work/guides/contracts/`; inspect actual callers and guards. No cosmetic file splitting or line quotas.
