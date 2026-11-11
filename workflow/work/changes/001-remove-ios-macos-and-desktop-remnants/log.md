# Log 001-remove-ios-macos-and-desktop-remnants: Remove iOS, macOS and desktop remnants

<!-- Append-only. One line per decision, step or result: date, what, evidence (commit, command and result,
     file:line). Never rewrite an earlier line; add a correction below it. -->

## Entries

- 2026-11-11: change created
- 2026-11-11: T001 reconciled after an owner-requested early commit. The owner asked to push while T001 checks were still running, so 45e9aef (this task's own work) was committed and pushed before review. T001 head moved from 20ff0a7 to 45e9aef; base stays 20ff0a7 so checks and review still cover the whole change. The first check run failed only in the pub-cache flutter_local_notifications suite (Robolectric cannot read Java 25 class files); android-unit was scoped to the app and vendored third_party plugin tests on the owner's choice.

- 2026-11-11: Owner authorized committing T001 without the independent review and without rerunning checks; the rerun after the android-unit scope change was stopped. Evidence is the first full run (.work/runs/20261111T090503581819Z, code unchanged since): flutter analyze clean; 542 Dart test files passed, 0 failed; rust-lint clean; 557 Rust tests passed; :app, :audio_service and :ffmpeg_kit_flutter_new_audio unit tests passed; only the pub-cache flutter_local_notifications suite failed (Unsupported class file major version 69). T001 stays open in state.json: no clean review was recorded.

## Close

- Drift: [FILL: what the final code does that spec.md or plan.md does not say, and which side was updated; or "none"]
- Not verified: [FILL: device checks and paths no test covers; or "none"]
- Lessons: [FILL: a mistake seen twice and the check that now catches it; or "none"]
