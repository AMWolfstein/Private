## Migration status

This repo is being converted to a local/offline Android-only music player.
**Read `LOCAL_OFFLINE_MIGRATION_PLAN.md` (esp. `## Progress`) and `git log --oneline -10`
before continuing any migration work.**

The app targets Android and local files only. Mornye is its sole production theme; keep
light/dark modes and local storage, playback, lyrics, backup and USB support. Do not
reintroduce providers, downloads, extension credentials or remote artwork loading.

## graphify

This project has a knowledge graph at graphify-out/ with god nodes, community structure, and cross-file relationships.

When the user types `/graphify`, use the installed graphify skill or instructions before doing anything else.

Rules:
- For codebase questions, first run `graphify query "<question>"` when graphify-out/graph.json exists. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. These return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw grep output.
- Dirty graphify-out/ files are expected after hooks or incremental updates; dirty graph files are not a reason to skip graphify. Only skip graphify if the task is about stale or incorrect graph output, or the user explicitly says not to use it.
- If graphify-out/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).

## Feature-removal workflow

**Always use graphify first** when removing a feature (never start from raw grep alone):

1. **Plan** — read the latest graph (`graphify query` / `path` / `explain`, and
   `graphify-out/GRAPH_REPORT.md` if needed) to find every node/edge the feature touches and to
   confirm the blast radius before deleting anything.
2. **Remove** — make the code changes (cross-check paths with `grep` as you go).
3. **Confirm removal** — run `flutter analyze` (must be `No issues found!`) **and the full
   `flutter test`**; also re-query graphify / grep to prove no references remain. Fix until clean
   (the only accepted failure is the known-flaky `test/library_browse_sqlite_paging_test.dart`).
4. **Commit** — in the order below.

## Commit conventions

The workflow ends in **three separate commits** — never mix them:

1. **Code commit** — source, tests, config only (`lib/`, `test/`, `integration_test/`, `scripts/`,
   `pubspec.*`, Android files, etc.). The message describes the code change (`chore(offline): ...`).
   This commit must **NOT** include `graphify-out/` or `LOCAL_OFFLINE_MIGRATION_PLAN.md`.
2. **Graphify commit** — run `graphify update .` and commit only `graphify-out/` tracked files as
   `chore(graphify): refresh code graph after <phase>`.
3. **Docs commit** — `LOCAL_OFFLINE_MIGRATION_PLAN.md` (and `AGENTS.md`/docs if touched), e.g.
   `docs: record <phase> in progress tracker`.

Order: **code → graphify → docs** (graphify reflects the code commit; docs record the finished
work). Stage paths explicitly (e.g. `git add -u` then list `graphify-out/...` files); never
`git add -A` because generated artifacts (`.dart_tool/`, `build/`,
`lib/l10n/app_localizations*.dart`, `.flutter-plugins-dependencies`, `graphify-out/cache/`) are
untracked.
