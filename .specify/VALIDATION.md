# Spec Kit setup validation

Installed from official GitHub Spec Kit v1.4.0, source commit
`0019fa14d12f45edabc2cc3176c9168a68bd0f97`, on the existing `new-workflow`
branch. This setup does not execute archived feature plans or implementation tasks.

Verified:

- Official CLI generation with Codex `--skills` and Bash, no extension/global agent
  configuration or application dependency installation.
- `bash -n` passed for all six installed Bash scripts.
- Isolated temporary Git repository: create a feature/spec, set up plan, resolve
  tasks through the local override (the original map-task and final-review shape), validate required
  spec/plan/tasks artifacts, select a feature explicitly, and fail clearly with a
  missing feature pointer. The scripts did not change the temporary Git branch.
- Local template override was selected while the official task template remained
  available. Feature selection uses `specs/<number>-<name>` relative to the checkout;
  explicit selection can persist the ignored local feature pointer.
- Existing tool suite: **50 passed, 0 failed, 0 skipped**, using the installed
  CodeGraph CLI and pinned Bash-parser interpreter. Audit/navigation implementations
  and application source were unchanged by this installation.
- Local policy/constitution/skill/reviewer links, source provenance, Git diff
  whitespace and application-source scope were checked before commit.

Limitations:

- This validates installation and artifact scaffolding, not a completed AI feature
  implementation. Review rounds/one-commit rules are agent instructions; no hidden
  state machine or runtime enforcement gate was added.
- The optional generic upstream workflow runner does not declare Codex support;
  use the installed direct Codex skills. Its local YAML omits intermediate approval
  gates. Additional extensions and alternate agent/PowerShell integrations were
  not installed or tested.
- No Android build, APK, device test or new language-server provisioning occurred.
  Baseline application tests/builds were not rerun for this instruction/scaffold
  change.

## Map refresh at every task start

The local rule now starts task numbering at T001 and refreshes the map as the
first action of every task, including TOR and final review. No dedicated map task
or map-only commit is generated. The active task-template resolver was exercised
successfully; generated structure, policy/skill consistency, links and diff checks
passed. This update changes instructions/templates only; no application/tool source
changed and the tool regression suite was not unnecessarily repeated.
