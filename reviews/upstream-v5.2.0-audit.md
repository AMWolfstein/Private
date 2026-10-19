# Upstream v5.2.0 — initial compatibility audit

Status: **discovery and scanner comparison complete; wider behavioral audit incomplete; zero backports implemented**.
Date: 2026-10-19. Authoritative local source: `2b323612a7e473ef9a4e5d6a48ebb071add25924`.
Branch: `review/upstream-v5.2.0-discovery`. Upstream: [repository](https://github.com/spotiflacapp/SpotiFLAC-Mobile) / [release](https://github.com/spotiflacapp/SpotiFLAC-Mobile/releases/tag/v5.2.0).

## Scope and method

This is the first bounded work unit, not the final integration review. Release notes were read, then Git history, changed paths and selected source hunks were compared with current retained implementations. The complete [commit inventory](upstream-v5.2.0/commits.csv) has **238 entries**, including one merge; the [path inventory](upstream-v5.2.0/paths.csv) covers **858 changed paths** (858 files changed, 72325 insertions(+), 42615 deletions(-)). Counts describe the chosen comparison interval, not independent feature counts.

Evidence levels: **17 SOURCE_REVIEWED** entries have focused behavior/dependency comparisons; **1 PARTIAL_SOURCE_REVIEW** entry has only part of its implementation examined; **220 PATH_INVENTORY_ONLY** entries have commit/path and policy triage, not complete source review. Even source-reviewed entries can require more lifecycle/caller analysis before implementation. Do not interpret path inventory as proof of equivalence or safe adoption.

Every inventory row records full SHA, parents, source paths, current path presence/absence, local implementation status, dependencies, classification, scope/reason/benefit, complexity/risk, effort/tests and batch. Absent paths may have been removed or relocated; presence alone does not establish the same behavior. Mixed commits are classified for the explicitly stated scope; rejected portions are never implicitly approved.

## Baseline discovery

The repository is not shallow. Its parentless snapshot root is `47298e55b1eef2cfdbef1f7b80570a164bfa2f3b` (subject `s`), with no Git merge base against target `22f3ec52f9bd1e57f661ca0b17e3aaa34b0e8ae8` (`git merge-base` exit **1**). Genuine upstream ancestry cannot be reconstructed from that snapshot. **No invented merge base or fork point is asserted.**

The strongest content baseline is `5a8952659b247fd95f1914a56db60825657fe26d` (`chore: update AltStore source to v5.1.1`), immediately after the v5.1.1 tag commit `78699a91637ceeb57f837b6e2cff2262d3c41da8`. Comparing its tree to the local root yields only these four missing files:

- `docs/artist_concerts.md`
- `docs/player_widgets.md`
- `rust_backend/vendor/libusb1-sys-0.7.0/Cargo.toml.orig`
- `rust_backend/vendor/rustix-1.1.5/Cargo.toml.orig`

All runtime/build source contents otherwise match that upstream snapshot. Active vendor Cargo manifests match; the two `.orig` omissions are archival manifests. This is **high-confidence content equivalence**, not proof of ancestry. v5.1.1 alone differs additionally in `apps.json`; therefore it is a less exact content baseline. Baseline→target includes **238 commits**, while v5.1.1 tag→target includes 239 (the extra AltStore commit).

Pin target to peeled release commit `22f3ec52f9bd1e57f661ca0b17e3aaa34b0e8ae8`, tree `49ad3f63f9854b79d8162f0d19e9bfb73c2152b2`; tag object `2184bd1159822c75a2b6b6d4cd0ade49a908a3e4`. Do not follow later upstream main. Local remote is `https://github.com/AMWolfstein/Private.git`. Discovery fetched public history into `refs/remotes/upstream-audit/v5.2.0` and created a review branch; no main/work branch source was changed. Reproducible tree/ancestry/count evidence is in [evidence.json](upstream-v5.2.0/evidence.json).

## Architecture and exclusion guardrails

Verified: Flutter/Dart UI, Mornye production theme, Rust core/local/mobile workspace and Kotlin/Android channels; local library, tags, artwork, lyrics, playlists and statistics retained. The current source is 5.1.1+166; no upstream version reset is appropriate. Current normal/immersive player choice already exists.

Do not restore streaming, providers, downloads, online lyrics/search/recommendations, regional extension settings, remote artwork or network permissions/dependencies for upstream features. Preserve removed metadata-details route, Wishlist, conversion, obsolete settings and Recent overview removals; keep per-file Edit Metadata, local lyrics/ReplayGain/CUE functions. No Media3/Sistrum, Rust DSP or multiband EQ work in this phase. No user music files are touched by this audit.

**Existing discrepancy:** production enum only offers Mornye, but `pubspec.yaml` still declares `material_ui`, `material_3_expressive` and `material_color_utilities`; `app.dart` and some shared widgets retain imports/helpers. This predates this audit. User policy forbids restoring Expressive; it is inaccurate to claim its entire footprint is already absent. Record an independent investigation of the residual dependency graph, without removing working shared primitives in this docs-only unit. All proposed UI adaptations must use retained primitives and add no Expressive infrastructure.

## Compatibility matrix

The table summarizes focused decisions. Complete per-commit policy triage, including unreviewed changes, is in the CSV. ADAPT means only the stated behavior is approved in principle; test/caller/lifecycle gates in the backlog still apply. No cherry-picks or source changes occurred.

| Change (upstream SHA) | Classification | Reason | Benefit | Risk | Priority |
|---|---|---|---|---|---|
| fix(lyrics): refresh LRC sidecars in their actual SAF folder (`186c66ae`) | INVESTIGATE | Upstream validates actual SAF ancestry instead of assuming slash-delimited IDs. User-owned sidecar writes require reachability analysis and safeguards before approval. | Potential prevention of wrong-folder/failed sidecar updates; applicability not yet established. | High: writes to user-owned files | P1 |
| feat(library): add sectioned browsing and adaptive fast scrolling (`83a55fb8`) | INVESTIGATE | Speed-relative thumb and fine dragging may fit Mornye, but current pagination, variable-height rows, selection and intentional overview removals need a focused comparison. | Potential large-library navigation usability. | Medium/high: scrolling, paging and selection | P3 |
| fix(audio): preserve FLAC precision in Android bit-perfect playback (`3dc2d690`) | DEFER | User defers playback architecture and complex legacy processing. Upstream title is not proof of local sample truncation. | Potential bit-perfect correctness; no local fixture measurement yet. | High: decoder, ABI, output and native lifetime | Deferred |
| fix(settings): use shared sheet for log level selection (`8ff1490d`) | ADAPT | Full patch inspected: selected level changes after mounted check. Retain local page structure and use existing Mornye controls. | Consistent accessible level picker without rebuilding removed settings or introducing a UI system. | Low/medium: focus, filtering, sheet dismissal | P3 |
| feat(player): add configurable full-screen cover art (`05a56133`) | ALREADY IMPLEMENTED | Local explicit user choice already provides retained behavior; upstream playerCoverStyle must not duplicate it. | No backport needed; preserve current Normal/Immersive behavior. | Low if unchanged | Done/equivalent |
| test: declare the path provider interface dependency (`317cd254`) | REJECT | Upstream test hygiene applies when its tests import the interface. Do not add an unused declaration unless an approved backport requires it. | None until a retained test directly imports it. | Low | Excluded/currently unnecessary |
| perf(lyrics): cache timed lyric segment geometry (`afab47ae`) | ADAPT | Source adds width-keyed segment rectangle caching with invalidation. Manual adaptation avoids unrelated sharing/provider changes. | Avoid redundant layout work by inspection; no frame-time measurement claimed. | Medium: resize and script geometry | P2 |
| fix(player): report Android output failures without skipping tracks (`f426b2d1`) | INVESTIGATE | Returning false can permit MediaPlayer completion after an unhandled error. Confirm exact local event sequence before approving a narrowly scoped legacy-engine exception. | Potential prevention of accidental track skipping on output failure; not a verified device defect yet. | High: playback state and focus | P0 investigation |
| fix(library): restore bit depth as the default quality badge (`75907951`) | REJECT | Upstream changes fallback to bitDepthOnly; conflicts with current explicit local design decision. | None for this fork. | Avoid regression by rejecting | Excluded |
| fix(library): recover missing local album artwork from audio (`080df889`) | ADAPT | Upstream checks missing/empty files and recovers embedded artwork with stale-request guards. Adapt into retained widgets rather than importing whole builder. | Recover locally available artwork when cache path is missing; preserve existing covers. | Medium: async identity, cache lifetime and dimensions | P2 |
| perf(library): build DateFormat and RegExp once instead of per row (`acbc614f`) | ADAPT | Extract retained helper optimization without restoring removed routes, online album page or alternate library layout. | Avoid repeated regex construction in retained helper; no measured performance claim. | Low: Unicode alignment semantics | P2 |
| ci: run the Android Rust build once and cache Cargo (`4c78f476`) | DEFER | Useful least-permission/cache principles require independent fork-specific CI plan, not restoring removed publishing machinery. | Potential reproducible build efficiency, unmeasured and not applicable to existing workflow. | Medium: CI secrets, permissions and build matrix | Deferred |
| build(rust): drop unused direct dependencies and centralize pins (`5254760b`) | ALREADY IMPLEMENTED | Unused online dependency objective already achieved more broadly. No reason to restore crates or overwrite local Android patches. | No backport for removed crates; pin reshuffle is optional cleanup. | Low if unchanged; medium for manifest edits | Done/equivalent |
| perf(lyrics): compile credit regexes once (`ef5fa1cb`) | ADAPT | Equivalent constant regex reuse can be adapted independently of online storage-message cleanup. | Avoid repeated compilation/allocation by inspection; no benchmark or runtime speedup measured. | Low/medium: preserving lyric text and credits | P2 |
| refactor(core): add fs::write_atomic and use it for the atomic file writes (`190801c3`) | DEFER | Current atomic safety is already present at retained export site. Shared-helper cleanup has low benefit relative to write-policy regression risk. | Potential maintainability only, not proven new integrity protection. | High: user-file write semantics | Deferred |
| refactor(playlists): share the playlist name prompt and dispose its controller (`fe29f304`) | ADAPT | Upstream StatefulWidget owns and disposes controller; fits retained local create/rename flows through manual adaptation. | Consistent validation and bounded controller lifetime. | Low/medium: validation, focus and cancellation | P2 |
| fix(library): recover interrupted scans and stale notifications (`378c8f37`) | ADAPT | Source shows a fallible persistence call precedes UI cleanup and upstream serializes notification updates. Adapt smallest safeguards; inspect lifecycle/cancellation before implementation. | Preserve original source error/failure notice after secondary DB failure; avoid stale notices; later report interruption. Outer finally already resets scanning. No performance claim. | Medium: lifecycle, checkpoint and source-state ordering | P1 |
| feat(crash): show persistent crash reports on Home (`cb51d089`) | INVESTIGATE | Bounded/redacted reporting could aid offline support, but handled error vs confirmed process death, native retention/privacy and startup ordering remain open. | Potential locally inspectable crash evidence; no telemetry required or authorized. | Medium/high: startup and diagnostic data | P2 investigation |
| fix(crash): match the Home crash card to the error card style (`36694c6e`) | INVESTIGATE | Stat/message establish follow-up behavior, not sufficient native/UI compatibility evidence. Not automatically Material-only: review retained behavior independently. | Potential readable long crash report, contingent on I04. | Medium | P3 investigation |

## Detailed scoped decisions

Full SHAs, changed source files, local counterparts, dependency impact, complexity, risk, effort, tests and reasoning for the table entries are preserved in [source-reviewed.json](upstream-v5.2.0/source-reviewed.json), including the explicitly partial and inventory-only investigations. Source inspection was focused on the behavior described, not a certification of every hunk of a large mixed commit.

- Scanner: detailed [comparison and patch plan](upstream-v5.2.0-scanner-review.md) complete. Error persistence can suppress original failure visibility, but outer startScan finally already resets scanning/admission. Independent notification futures can finish after terminal/pause. Split into B01a failure/notification correctness, B01b restart reporting and B01c optional native exit diagnostics; no upstream source splitting.
- SAF sidecars: do not patch user-file publication until retained editor reachability and opaque-ID ancestry are understood. Leftover re-enrichment references alone do not establish active use.
- Playback: output-error completion and FLAC precision are separate questions. The former merits a focused critical-correctness investigation; the latter needs sample evidence before any exception to the legacy-engine freeze. New decoder/EQ/AutoMix/haptics architecture remains deferred.
- Artwork: preserve the fork's actual-image layout fix and bounded local resolver. Do not replace current components wholesale or add remote fallback.
- UI: playlist controller disposal, timed lyric geometry, pronunciation regexes and a Mornye Logs sheet can be small independent adaptations. Upstream Expressive buttons/forms/settings must not accompany them.
- Rust atomic writes: retained export already uses atomic staging. Generic helper consolidation is not automatically a new integrity fix; no-clobber, cancellation and fsync semantics require individual review.
- Security: no vulnerability database or dependency security scan was run. No claim is made that all security issues are evaluated or that performance improves at runtime.

## Broader inventory coverage and unresolved work

All commits/paths are indexed across Flutter, Rust, Kotlin/Android, scanner/SAF, metadata, artwork, lyrics, collections, statistics, resource management, UI/accessibility/tablets, dependencies/build/CI, tests and docs. Detailed semantic comparison is incomplete in each broad subsystem. Specifically investigate retained metadata mapper/sidecar publication, playlist cover I/O, ingestion/schema helpers, incremental scan completion/cancellation, resource disposal/coalescing, contrast/semantic labels, tablet insets, skeletons, mini-player/queue feedback and timed-vocal transitions. Their inventory classifications are provisional, not permission to mechanically port refactors.

Policy-rejected entries include whole Material/Expressive and online-service imports. Mixed general-purpose commits can yield independently reviewed local adaptations later. Native engine/DSP changes, broad module splits and upstream publishing automation are deferred. The current `.github` directory is absent; do not recreate upstream iOS/online release workflows. Existing local CI scripts/build integration must be evaluated independently.

Dependency manifest source comparison found: upstream secure-storage compatibility downgrade/Apple override (removed credential feature; reject), Material Symbols dependency (reject), vendored Darwin player override (Android-only fork; reject), direct path-provider interface dev declaration (not directly imported by retained tests, currently reject), FLAC native license asset (defer with decoder). Dart SDK constraint and `.fvmrc` do not change in this interval. Rust cleanup centralizes existing pins/removes online direct deps; do not overwrite current Android rustix/libusb compatibility patches. Resolved transitive/lock/native dependency effects still need a dedicated comparison before any package updates; no blanket update is approved.

## Initial classification totals

| Classification | Commit entries |
|---|---:|
| ADOPT | 0 |
| ADAPT | 7 |
| ALREADY IMPLEMENTED | 2 |
| REJECT | 46 |
| DEFER | 138 |
| INVESTIGATE | 45 |

These are commit-level scoped decisions; zero ADOPT entries means no commit is approved for unchanged wholesale cherry-pick. A source-reviewed subset may be ADAPT while other hunks remain rejected/deferred. The final report must recount final behavior-level decisions and implementation traceability after all comparisons and approved batches are complete.

## Checkpoint and continuation

No application, configuration, dependency, schema, generated bindings, graph or user-media changes in this unit. The [prioritized backlog](upstream-v5.2.0-backlog.md), [verification record](VERIFICATION.md) and [handoff](HANDOFF.md) are the continuation contract. Graph is current for unchanged application source, last synchronized at `81577e50` for source `6ac8efd0`; no regeneration needed for review documents.

**Next exact work unit:** implement **B01a only**, the minimal failure-visibility and ordered scan-notification adaptation from `378c8f374987c6a8a8f8cbf6330736f136414d94`, following [scanner review](upstream-v5.2.0-scanner-review.md). Add fault/race regressions, run targeted checks/analysis, synchronize Graphify, commit and push. Do not implement B01b/c, change native scanning/publication or build an APK in that unit. Recommended effort: **HIGH**.
