---
name: quick
description: "Quick changes: documentation, comments, wording, a config value or a small local code edit with no contract, data or high-risk impact. Edit, run only the fast checks for what changed, review the diff once, commit and push straight away. No change record, task loop or full suite."
---

# Quick changes

The owner wants small things done fast: edit, review, commit, push. No change record, no task
commands, no map rebuild, no full test suite.

## When a change is quick

Either of these:

- Text only, in any path: Markdown and other docs, licence text, translations, or comments.
- A config value or a small edit in one place in the code, outside the `high_risk` paths in
  `workflow/work/checks.json`.

And all of these hold:

- It changes no contract or stored data: no channel or method name, payload field, schema,
  migration, preference or backup key, file format, public API or dependency version.
- It has no planning question: one obvious way to do it.

Otherwise use the fix skill (bounded behaviour) or spec/plan (larger work). When unsure, it is not
quick. If a quick change grows past these limits while you work, say so and switch to the fix skill.

## Steps

1. Read the files you change and find their direct users with `rg`. Edit.
2. Run only the fast checks for what changed, and report each with its result:
   - Markdown, licence or other text files only: no check.
   - Translations (`.arb`): `flutter analyze`, which regenerates the localizations.
   - Dart: `dart format` on the changed files, `flutter analyze`, and the test files that import
     a changed file (`rg -l` for its import) or the changed test itself.
   - Comments in Kotlin or a Gradle file: `bash android/gradlew -p android :app:compileDebugKotlin`.
   - Comments in Rust: `cargo check --locked` in `rust_backend`.
   - Workflow scripts: `python3 workflow/scripts/work/run_tests.py`.
   A failure the edit caused is fixed in place. A failure it did not cause is reported, not fixed.
3. Review the diff once. Prefer a fresh read-only reviewer given only `git diff`, the request and
   the `code-reviewer` prompt; otherwise re-read the whole diff yourself and say it was a
   self-review. Fix real findings. A finding that shows the change is not quick moves it to the
   fix skill.
4. Commit the explicit paths in one commit (what, why, the checks and their results, what was not
   verified; no model names) and push the current branch immediately. A quick change needs no
   separate push request.

A bug fix that changes behaviour keeps its regression test (constitution IV), even on this path.
