# Architecture contract

Status: target responsibilities, not a claim about current files. Map these roles onto actual paths in `workflow/work/architecture.json` once the paths exist (modules with responsibility, owned state, allowed dependencies; constraints with forbidden imports; each `reviewed` or `proposed` with its source). Keep names and folders minimal; add modules only for real ownership boundaries.

## Direction and ownership

Flutter widgets → Dart presentation/client API → platform bridge → Kotlin application coordinator → engine/data interfaces → Media3, Android storage and pure Kotlin implementations.

- Flutter owns rendering, navigation and transient UI state. A screen observes authoritative playback state; it does not become a second playback coordinator.
- Kotlin's MediaLibraryService owns background playback/session/notification/Android Auto/media buttons and widget updates. Its coordinator owns queue, shuffle/repeat, restore, history, sleep timer, autoplay and AutoMix decisions.
- Engine/DSP/decoder interfaces do not depend on Flutter widgets or channel maps. Pure Kotlin codecs/DSP/analysis do not import Android/Media3 APIs; Android adapters do.
- A narrow boundary translates wire values into domain types. Domain logic must not spread channel names, untyped maps or transport exceptions throughout the application.
- One owner per mutable state/resource; specify lifetime, dispatch context and disposal. Initialization is explicit and idempotent where required. Avoid widget-triggered global initialization, hidden service lookups and competing startup paths.
- Reuse platform facilities or existing code when they meet the full contract. Do not introduce a layer, bus or repository wrapper merely for symmetry.

## Storage and concurrency

Kotlin must access data required while Flutter is absent. Define database/schema ownership, migration coordination, transactions, WAL and cross-process/thread access before sharing files with Dart. Same database filename does not imply safe concurrent caches or compatible SQLite features. Keep library IDs, collection links, backup compatibility and cover identities stable where promised.

Background native jobs and playback need explicit cancellation/commit semantics. Cancellation cannot retract a committed write; finishing a temporary file is not necessarily publication. Closing an Activity must not destroy service-owned playback. A stale callback cannot overwrite a newer generation.

## Policy enforcement map

| Rule | Evidence required | Current automation |
|---|---|---|
| Layer direction and single state owner | Imports, direct callers, architecture review | `work.py context` reports possible import-level violations of `architecture.json` `may_depend_on`/`forbid_imports`; ownership itself is review judgment |
| Channel compatibility | Dart and Kotlin contract tests with shared cases | Must be implemented in app; starter provides contract checklist |
| Publication and cancellation | Failure-injection and lifecycle tests | Must be implemented per operation |
| Background operation without Dart | Android service/device tests | Device gate, never a host-mock pass |
| No redundant abstractions or cosmetic splits | Responsibility/API review | Human/agent judgment |

Extend this map with actual enforcing commands and test paths. Do not label a prose rule mechanically enforced.
