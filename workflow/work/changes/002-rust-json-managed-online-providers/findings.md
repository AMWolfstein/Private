# Design findings

### F-001 [design r1, goldfish-reader+design-critic] Schema and route inventory unspecified
- Severity: major
- Status: fixed
- Evidence: plan Review clarifications specifies schema v1, 12 request origins, 64KiB bound and rejection rules.

### F-002 [design r1, goldfish-reader+design-critic] Artwork inventory incomplete
- Severity: major
- Status: fixed
- Evidence: all 13 sources, capabilities and fixture/caller requirements listed; later required batch remains incomplete.

### F-003 [design r1, goldfish-reader+design-critic] Authentication and installation missing
- Severity: major
- Status: fixed
- Evidence: Ed25519 envelope, bundled keys, atomic cache persistence and deferred operator distribution documented.

### F-004 [design r1, design-critic] Cache generation invalidation unspecified
- Severity: major
- Status: fixed
- Evidence: restart-only activation; independent per-revision persisted lyric cache and new backend token/coalescing owners.

### F-005 [design r2, goldfish-reader+design-critic] Conflicting hot-swap sentence
- Severity: nit
- Status: fixed
- Evidence: original Updates paragraph changed to restart-only activation.

### F-006 [code r1, storage reviewer + author] Preserve typed installation failures
- Severity: nit
- Status: fixed
- Evidence: Backend::install_provider_configuration now returns ConfigError; Backend restart tests assert distinct Revision, BackendUnavailable and Authentication outcomes. Both reviewers returned CLEAN on .work/review/002-code-r2.md.
