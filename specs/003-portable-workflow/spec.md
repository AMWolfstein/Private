# M003 — Portable workflow and safe setup history

The owner requests that setup creates root TASK_HISTORY.md when absent and never
replaces an existing history file. They additionally request the workflow in a
single transferable workflow/ folder, with a comprehensive README.

Acceptance:
- All executable helpers, analysis adapters, manifests and portable instruction/
  template defaults are shipped under workflow/. Root AGENTS.md/history and
  project task records remain repository-local; Spec Kit can keep installed root
  .agents/.specify copies for its normal discovery/layout.
- Copying workflow/ to another Git repo and running setup installs missing local
  requirements and missing support files without copying Mornye task data.
- Existing TASK_HISTORY.md bytes/mtime are preserved by every setup mode/retry.
  Missing history derives from a valid local registry, or starts empty for a fresh
  project. Existing ambiguous project state is retained and reported incomplete,
  never silently reset or imported from the distribution.
- README documents transfer, bootstrap, tools, plan/quick-task loops, global IDs,
  history, CI and limitations. Core instructions remain agent-neutral.
- Preserve IDs, completed history and app behavior. No APK/global agent config or
  application dependency changes. Task allocation/completion uses existing helper.
