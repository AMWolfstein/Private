# Lessons

A mistake becomes a rule here after it happened twice, and only with the check that enforces it. Prefer, in
order: structure, type, lint or test, hook, and prose last. Prove each check: reintroduce the mistake, see the check
fail, remove it, see it pass. A rule without enforcement that is broken again counts as a repeat.

## Enforced (seen at least twice)

| Mistake | Seen | Enforced by | Proof |
|---|---|---|---|
| `pkill -f <pattern>` matched the agent's own shell and killed it (exit 144) | 2× (2026-10-31) | `work.py hook-bash` blocks `pkill -f` / `--full` | `test_work.py` `test_guard_blocks_pkill_full` |
| The whole `flutter test` run stalled between files with no test running; waiting looked like progress | 3× (2026-10-31) | `work.py check dart-tests` runs one top-level folder at a time, kills a chunk silent for 600 s, retries once, reports STALLED | `test_work.py` `test_stall_is_retried_then_reported` |

## Safeguards from a single incident

Kept because the check is cheap and the incident was costly. Promote to the table above on a second occurrence.

| Incident | Enforced by | Proof |
|---|---|---|
| A regression test passed with the fix removed, so it proved nothing (2026-10-31) | `work.py prove -- <test command>` reverts non-test changes and requires the test to fail | `test_work.py` `test_prove_*` |
| A Kotlin compile error was found only by the APK build because only Dart checks ran | `work.py check auto` maps `android/*` changes to `android-unit` (Gradle compiles main sources) | `test_work.py` `test_auto_selects_checks_by_path` |
| Keyword routing classed "export" and "التنقل" as migrations (substring matches) in an earlier workflow draft | Size comes from changed paths (`work.py scope`) and the owner's intent, not keywords | `test_work.py` `test_scope_uses_paths` |
