# Work queue

Authoritative details: [v5.2.0 backlog](upstream-v5.2.0-backlog.md) and [audit](upstream-v5.2.0-audit.md).

1. **Next invocation, one comparison unit:** B01 scan recovery and notification ordering (`378c8f37`), HIGH. Resolve lifecycle/API/checkpoint/data-retention guards and targeted test plan. No other subsystem implementation.
2. Narrowed implementation units only after comparison: B01; then B02 playlist controller ownership; B03 Rust local credit regexes; B04 artwork; B05 timed lyrics; B06 pronunciation constants; B07 Logs sheet. Keep each independent.
3. Prioritized investigations: I02 playback output-error completion (P0 candidate, not confirmed); I01 SAF sidecar integrity (P1); I04 local crash diagnostics; I03/I06–I09 scrolling/a11y/tablets/mini-player/lyrics.
4. Complete remaining subsystem and dependency/security comparisons recorded in CSV. Provisional DEFER/path-only decisions are not a completed behavioral audit.
5. After approved implementations: final compatibility review, broader regression/build verification and `upstream-v5.2.0-final-report.md`, with upstream/local commit traceability and no unearned regression-free claim.

Permanent guards: no online features or Expressive restoration; no future Media3/Sistrum/Rust DSP implementation; preserve retained local editing, artwork, lyrics, stats and collections. No user-file operations or metadata migrations without the required safeguards/authorization.
