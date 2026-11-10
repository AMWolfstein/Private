# Fortnightly upstream review proposals

All implementation and the workflow template live in this directory. **This is not
an active scheduled GitHub Action:** GitHub only discovers workflow files under
`.github/workflows/` on the repository's default branch. The owner requested that
this addition stay inside `extensions/`, so no launcher was installed outside it.

## What the watcher does

- Inspects `mornyeapp/Mornye-Extension` for the 13 included JavaScript artwork/Apple
  lyrics sources, their manifests, new text helpers under those provider directories,
  license notices and the copied Apple artwork/lyrics tests. Jellyfin is excluded.
- Inspects `mornyeapp/Mornye` for built-in Rust lyrics providers, shared lyrics
  parsing/matching and the extension lyrics ABI/normalizer.
- Compares immutable commit/blob IDs against `state.json`. The initial extension
  baseline is the imported upstream commit; the initial native baseline is hashed
  local Rust source, explicitly not claimed to be an upstream commit.
- Generates a report and review-only unified diffs under `reports/` and `patches/`.
  It proposes a reviewed-version state update alongside the report.
- Opens a **draft PR** targeting `extension-system`. It leaves an existing open
  upstream-review PR alone and does not rewrite or reopen an existing proposal branch.

**It does not modify the provider implementations.** Rust changes still need native review and adaptation to the supported JSON schema;
upstream JavaScript changes must be manually ported to Rust with fixture tests.
Extracted JavaScript references still need dependency and permission review. No downloaded upstream code or tests are executed. Merging a
report-only PR acknowledges reviewed upstream versions, not completed source updates;
apply and validate relevant changes in the PR before merging, or close it to keep the
old baseline. No imported source pins or native-port origin locks are advanced by
this watcher. Those track implemented code, separately from reviewed versions.

There is no automatic merge, source-package publication, APK build or deployment.

## Files

- `watch.json`: curated repositories, branches, watched paths and fortnight anchor.
- `state.json`: reviewed baseline commits/blob IDs, updated only in proposed PRs.
- `watch.py`: bounded read-only public GitHub requests and review bundle generation.
- `publish.py`: normal Git branch/commit/push and draft PR creation using GitHub CLI.
- `workflow.yml`: ready-to-install GitHub Actions workflow template.
- `tests/`: offline watcher/publisher tests, including deletion and error cases.

The Python scripts use only the standard library. Ubuntu GitHub-hosted runners need
Git, Python 3, Node.js 22+, npm and `gh`; existing source checks use the pinned parser
dependencies already under `extensions/tools/`. The write token is only passed to
the publisher step; public upstream reads do not send a repository token.

## Scheduling and activation

The template triggers every Monday at 06:17 UTC. `watch.py` only performs upstream
checks on alternating Mondays anchored at 2026-11-09, giving a 14-day cadence.
Other scheduled weeks make no upstream requests. Manual dispatch defaults to forcing
a check regardless of that date. GitHub schedules are best effort, not exact timers.

When the owner permits the required exception to the folder-only constraint:

1. Place `workflow.yml` at `.github/workflows/extension-updates.yml` on the default
   branch. No existing CI or release workflow needs editing.
2. Keep the template's checkout `ref` and `watch.json`'s `target_branch` aligned;
   both currently target `extension-system`, where the implementation lives.
3. Enable Actions and the repository setting allowing GitHub Actions to create pull
   requests. The workflow requests `contents: write` and `pull-requests: write` for
   its built-in token; it does not require a personal access token.
4. Run one manual dispatch to verify real repository permissions and PR creation.
   These permissions have not been verified merely by testing the scripts locally.

No such activation or real review PR creation is performed as part of this addition.

## Local checks

```sh
python3 -m unittest discover -s extensions/updates/tests -v
# Inspect actual upstream changes without writing state, patches, branches or PRs:
python3 extensions/updates/watch.py --force --dry-run
```

`watch.py --force` without `--dry-run` prepares review files in the current checkout;
it does not itself push or create a PR. `publish.py` is intended for the workflow's
clean checkout, after tests and a successful scan. It refuses unrelated working-tree
changes and stages only the generated review paths. Network failures, truncated API
trees or mismatched blobs abort the scan before any proposal is written. If initial
native baseline content is unavailable, the report names that gap instead of making
up a diff. Upstream text is retained as patch data; whitespace attributes for patch
files preserve meaningful blank-context lines without disabling source-code checks.
