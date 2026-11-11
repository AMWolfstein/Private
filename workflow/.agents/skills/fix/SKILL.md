---
name: fix
description: "Bug fixes and small changes: one behaviour, a few files, no contract, schema or file-format change. Finds the root cause, writes a regression test that fails without the fix, makes the smallest complete change and verifies it."
---

# Small changes

Choose this path for one bounded behavior with no new architectural decision, cross-language
contract, data schema/format migration or multi-part implementation. Size is impact, not lines.
Text-only edits (docs, translations, comments) and config values or small local edits outside
high-risk paths take the lighter quick skill instead.
If the scope grows, explain why and enter planning before expanding it.

1. Use `new "title" --size small`. This creates minimal tasks/state/log records, no spec/plan
   stage or planning commit. T001 implements and reviews the complete
   small change as the final task; task start refreshes the map. Follow the same task loop in implement/SKILL.md.
2. Read task context and actual callers/guards. State the bug's cause before changing it.
3. Make the smallest complete change. Preserve validation, files, accessibility and contracts.
   A bug needs meaningful regression coverage; use `prove --expect-failure` when establishing
   a regression against the old implementation. Do not invent tests for cosmetic edits.
4. Run appropriate checks, independent review and fixes until clean, at most three reviews.
   Then prepare completion and commit implementation/tests/fixes/records together once.
5. Report what changed and the verification. Extra owner requests become TOR###; no automatic
   push/APK. Never treat missing analysis, inferred map edges or mocked device calls as proof.
