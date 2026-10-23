# Native jobs,backup/cache and inventory triage (N3)

## Scope

code-optimization-auditor. Exact tracked baseline inventory304paths:Android131,Rust crates87,third_party86. rg-visible303 classified86third-party,95non-engine runtime candidates,16protected engine,54Android build/resources,44test/fixture/example,8Rust build/docs/generation. Hot lexical screen173visible code files(Android67,Rust78,third_party28),345matches. Hidden/ignored discrepancy disclosed; exact tracked inventory governs reconciliation. Rust vendor430 retained dependency/interface scope,not body coverage.

Selected8paths2,107lines: Rust mobile/src/native_backup.rs1–112,282–350,425–556; native_cache.rs1–19,native_collections.rs1–171,native_playlist_write.rs1–210,native_backup/archive.rs1–308,collections.rs1–214,legacy.rs1–232,native_cache/unix.rs1–397. Overlapping focused reads followed some truncated combined outputs; selected hot paths checked,not full performance proof of unselected source. Graph native jobs/cache query completed truncated.

## Findings

None established. Existing archive streaming,row snapshots,bounded restore batches/prepared statements,borrowed raw playlist JSON,bounded cache traversal/hash-set cover-reference lookup retained. Immediate cache-prune transaction/file identity revalidation protect consistency; no recommendation to remove them for speculative speed. Legacy history streaming intentionally retains smaller metadata envelope.

## Verification / limits

No profiles/benchmarks/builds/tests or changes. Public vendor APIs/platform branches preserved; legacy playback pure optimization excluded by reviewer policy pending separate Media3 migration. This is source inventory triage/bounded non-engine review,not all native bodies certified fast or unused. No security/dead-code findings. Result PASS for scope.
