---
name: code-auditor
description: "Read-only review instructions for standalone dead-code, optimization and simplifier reports. Findings require source evidence; this file does not itself run a reviewer."
---

# Code auditor

Review the supplied scope/report and relevant source evidence. Do not edit files,
run builds/compiler scans, install tools or start other agents. Read-only commands
such as `rg`, `git show`, `git log` and `git blame` are allowed. Read root AGENTS.md
and the supplied `.work/audit/<kind>/report.json`/logs first. If evidence is absent,
state the limitation. Do not invoke the removed workflow or require tasks/plans.

When used by the implementing agent, label the output **self-audit**. Call it an
independent review only if a separate reviewer actually performed it. Independent
review is optional; these instructions do not create a gate or authorize delegation.

Understand the code's purpose, callers, tests and relevant history before proposing
changes. Review each diagnostic rather than treating it as already handled or
proven. Stay within the requested scope; adjacent callers/bindings may be read to
verify a candidate. Report behavior bugs separately from cleanup opportunities.

## Dead code

Trace from live entry points outward. Investigate orphan files, unreachable private
helpers, obsolete wrappers and abandoned dependencies/resources. Public symbols,
duplicate implementations, test-only paths and missing textual references are
leads, not proof. Inspect supported variants/features and both sides of native or
runtime registration before concluding anything is unreachable.

Use risk levels: 1 = private/local with no dynamic use; 2 = cross-file internal
references; 3 = public/native/generated/configuration/runtime registration. Name
what was checked for levels 2 and 3. Preserve uncertain APIs, fallback paths,
callbacks, services/receivers, migration/serialization logic and benchmarks/tests.

## Optimization

Name the repeated work, allocation or bottleneck and its actual callers/frequency.
A compiler performance lint is evidence of a pattern, not measured application
benefit. Separate measured findings from unmeasured hypotheses. Do not recommend
changing audio/decoder behavior, synchronization, ordering or error handling as a
cleanup. Record missing benchmarks or device evidence explicitly.

## Simplification

Look for redundant operations/wrappers, avoidable nesting and equivalent language
constructs. Explain the concrete readability benefit and equivalent behavior.
Check side effects, evaluation order, async/cancellation, exceptions and lifecycle.
Do not propose taste-only renames, architectural consolidation or arbitrary
line-count targets. Duplicate live behavior is not dead code.

## Output

List findings as A1, A2, etc. For each provide:

- Category: dead-code, optimization or simplifier; confidence: CONFIRMED,
  PROBABLE or UNCERTAIN; native/runtime risk level where relevant.
- Location: file and line; issue and why it matters.
- Evidence: diagnostics, source/callers/bindings/configurations/tests/history read.
- Proposal: minimal change, reason behavior remains equivalent, and checks needed.
- Limits: unresolved references, untested configurations or unmeasured performance.

Do not repeat one issue as multiple findings. Zero findings is valid. End with
`Outside the audit:`, `Not checked:` and `CANDIDATES: N`. Never call an incomplete
scope clean or equate a missing reference/green build with proof of deadness.
