# Native metadata/parser allocation and I/O (N2)

## Scope

code-optimization-auditor, source d5d5a02 unchanged. Eight paths3,730lines candidate-screened,124hot-operation matches. Full native_playlists.rs1–382; ranges native_lyrics.rs125–157,703–737,916–970,library_metadata.rs65–110,core/tags/containers.rs257–309,file.rs1–50,id3.rs112–153. comments.rs/mp4.rs candidate-screened; prior full immutable reads retained for contracts. Graph parser query completed truncated, navigation only. No edits.

## Findings

### PERF-004 [P2] [confidence: high] [NEEDS VERIFICATION]

- Location: rust_backend/crates/mobile/src/native_lyrics.rs:930–938, with_credits.
- Scenario: valid word-timed TTML loads parse/normalize complete XML for lyric lines,then repeat to collect credits even when songwriter metadata absent.
- Root cause: execute invokes parse_ttml then with_credits with independent normalized documents.
- Impact: additional CPU/temporary allocations each native TTML load; user-visible magnitude unmeasured.
- Fix: benchmark collecting credits during first traversal/reusing parse results while preserving distinct CDATA/malformed-document behavior.
- Evidence: execute139–152 calls both; parse_ttml707–716 and credits930–938 repeat normalization/document parse.
- Cross-refs: same file.
- Guards checked: TTML-only gate not credits-present gate; native worker avoids rendering cost but not load latency; passes intentionally differ in CDATA treatment, so not safely mergeable without parity checks. Coordinator independently inspected both paths.
- Required measurement:100/500/2000line valid TTML with/without songwriter/CDATA,total parse time/allocations/bytes and per-pass attribution; compare shared prototype against golden outputs. No speedup asserted.

### PERF-005 [P2] [confidence: medium] [NEEDS VERIFICATION]

- Location: rust_backend/crates/mobile/src/library_metadata.rs:68–83, descriptor metadata/cover reader.
- Scenario: Opus/Vorbis cover-cache miss with include_cover true reads/allocates comment packet for tags and again for artwork.
- Root cause: combined tag/cover pass only for FLAC; Ogg uses separate full readers.
- Impact: potential extra storage traffic/packet allocation for valid large artwork; magnitude/miss frequency unmeasured.
- Fix: benchmark combined bounded comment-packet extraction for metadata+artwork.
- Evidence: metadata then extract_cover in descriptor else branch; containers260 and281 independently call ogg_packets(reader,2,None).
- Cross-refs: tags dispatch/containers.
- Guards checked: FLAC combined already; include_cover false skips art; bounds prevent unbounded packet allocation but do not share reads; cache hit rate not profiled. Coordinator reread descriptor60–91 and containers257–296.
- Required measurement: counting Read+Seek wrapper,0.5/2/6MiB artwork fixtures,total bytes/seeks/peak allocation and cold/warm Android scan latency plus actual miss rate; preserve tag/cover parity.

## Verification / limits

Static traces, no benchmarks/builds/tests/profiles/devices. Prior RUST-001 parser-abuse/dead-code findings deliberately excluded; no engine optimization. Full-body performance proof not claimed for screen-only ranges. Result FINDINGS, two candidates requiring measurement.
