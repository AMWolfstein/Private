# Remaining tag readers and filesystem library identity

## Scope

RUST-01-B rust-safety-auditor, source d5d5a02 unchanged. Principal complete under rust_backend/crates/core/src/: tags/comments.rs1–311,containers.rs1–552,library.rs1–408,separators.rs1–21. S1/S2: rust_backend/crates/local/src/backend/library.rs35–120,library/scan.rs1–90,390–465,490–535; mobile/src/native_library.rs340–438,540–575; Android MainActivitySafScan.kt20–40 plus refs1038/1545,MainActivity.kt1120–1165; lib/providers/local_library_provider.dart815–837. Graph tags/comments/container query completed; ambiguous library_id explain retried with qualified source symbol successfully.

## Findings

### DATA-013 [P2] [confidence: high] [VALIDATED — static]

- Location: rust_backend/crates/core/src/tags/library.rs:19–24, library_id.
- Scenario: filesystem folder contains /music/ab.mp3 and /music/bA.mp3; scan assigns identical IDs, only one indexed row survives.
- Root cause:32-bit polynomial path hash has deterministic collisions and no collision resolution.
- Impact: valid local songs cannot coexist in indexed library despite intact backing files.
- Fix: collision-resistant deterministic path ID with migration/reconciliation of old identities.
- Evidence: hash*33+character;97*33+98 ==98*33+65; shared prefix/suffix preserve equality. library_metadata44 uses ID. scanner527 → scan_audio_file → backend/library106–110 shared reader/fallback. native_library375–383 unique stage ID and INSERT OR REPLACE; final568 replaces too.
- Cross-refs: local backend/scanner,mobile native_library,local_library_provider,MainActivity,MainActivitySafScan.
- Guards checked: SAF overwrites IDs with SHA1 at28–32/1038/1545, filesystem branch provider832/MainActivity1127 lacks that replacement. Uniqueness collapses records rather than resolving by path. Not duplicate of DATA-009 physical #track identity bug. Coordinator independently reread actual hash/metadata1–55; arithmetic proof static, no scan fixture executed.

## Verification / limits

No tests/builds/Clippy/device/mutation execution by reviewer. No unsafe-memory issue asserted. Genre repeated-comment reader first/last semantics remain compatibility follow-up, not promoted without contract. All four principal paths covered; supplemental endpoints ranged only. Decoder and writer bodies excluded. Result FINDINGS, one P2.
