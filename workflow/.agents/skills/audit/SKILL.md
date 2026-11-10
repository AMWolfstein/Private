---
name: audit
description: "Optional cleanup audit: dead code, simpler code and better-written code, for a language, a path or the files a change touched. Runs only when the owner asks or when a plan carries an [AUDIT] task. Tool-proven findings are applied directly; everything else is the owner's choice."
---

# Audit

Optional. Nothing in the task loop requires it, and no other skill starts it. It runs in two cases:
the owner asks for it, or tasks.md carries an `[AUDIT]` task.

## Scope

Always a named scope, never the whole repository in one run:

```sh
python3 workflow/scripts/work/work.py audit --lang rust                 # one language
python3 workflow/scripts/work/work.py audit --path lib/services/cast    # a file or directory (repeatable)
python3 workflow/scripts/work/work.py audit --change NNN                # files a change touched
python3 workflow/scripts/work/work.py audit --base COMMIT --lang dart   # filters combine
```

The command only reads. It writes `.work/audit/<scope>.md` (local, never committed) with the files in scope,
the findings a language tool proves, the keep list and the coverage gaps. Vendored and generated code
(`protected` in `workflow/work/audit.json`) is never audited. A language with no tool, or whose tool is not
installed, is a coverage gap: say so in the report to the owner, never "no dead code".

## Two kinds of finding

- Proven: the language tool reports it inside the scope (an unused import, element or variable, dead code).
  Apply these without asking.
- Candidate: everything else. Start a fresh read-only `workflow/.agents/reviewers/code-auditor.md` with the
  report path. Its findings (dead, simplify, rewrite; wave 1 to 3) go to the owner as a list ordered by benefit
  against size. The owner chooses; nothing is applied before that. If no fresh reviewer can be started, label
  the list as a self-audit.

A candidate that changes behaviour is not an audit finding. Report it separately.

## Applying

Code changes go through the task loop like any other change: inside the active `[AUDIT]` task, or, when the
owner asked outside a change, a `new "Audit <scope>" --size small` change.

- One kind per commit where the loop allows it (the unused imports, then the dead functions), so a regression
  can be traced. Inside one task, keep the kinds as separate, described groups in the log.
- After removing code run the checks of every domain it touched. A red check means the code was not dead:
  restore it and reclassify it as a candidate. Compilation is the proof; a missing text match is not.
- A rewrite is shown before it is made: the reason, before and after, the size of the diff. Code with no test
  covering it is marked unprotected; the owner decides between a test first or leaving it.
- Wave 3 (method channels, uniffi/JNI, the manifest, Gradle, reflection, config strings) is deferred unless the
  owner approves the specific item after both sides of the boundary were read.
- Never touch protected paths. Never widen the scope while applying.

## The [AUDIT] task

Optional line in tasks.md, single, directly before `[FINAL]`:

```
- [ ] T00N [AUDIT] Audit the files this change touched — check: auto
```

`task start` writes the audit report for everything the change touched since its base (its path is in the
result). Apply the proven findings, get the candidates from the code-auditor, apply only the ones the owner
already approved for this plan, and list the rest in log.md under `Audit candidates`. Then the normal loop:
`task check`, independent code review of the edits, one commit. An audit that changes nothing still completes
with its records. The `[FINAL]` task then reviews the cumulative result including the audit's edits.

## Keep list

When the owner decides a finding stays, add it to `keep` in `workflow/work/audit.json` with the reason
(`{"path": glob, "reason": text, optional "code", optional "contains"}`). Later audits stop reporting it.
Do not add entries the owner did not decide.

## Report to the owner

Scope and file count; proven findings applied (count, kinds, checks that passed after); candidates as a
numbered list with kind, wave, location, reason and estimated size; coverage gaps; what was not verified.
