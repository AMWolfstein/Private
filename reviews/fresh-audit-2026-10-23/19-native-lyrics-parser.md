# Native lyrics and tag-reader safety

## Scope

RUST-01-A rust-safety-auditor, source d5d5a02 unchanged. Complete under rust_backend/: crates/mobile/src/native_lyrics.rs1–1072,native_id3.rs1–261,library_metadata.rs1–267 (native_metadata.rs absent); crates/core/src/lyrics.rs1–3,lyrics/file.rs1–81,lyrics/lrc.rs1–46,tags/file.rs1–215,tags/id3.rs1–679,tags/mp4.rs1–252. S1/S2 mobile/src/native_xml.rs1–109,tags.rs245–310,data_jobs.rs1–75; core/src/tags.rs1–140,180–225,text.rs complete; lib/utils/lyrics_parser.dart209–248; lib/controllers/player_metadata_controller.dart1–30,80–150,170–210; targeted NativeDataJobs parser-limit refs. Graph query native lyrics/tag parser completed truncated, navigation only.

## Findings

### RUST-001 [P2] [confidence: high] [VALIDATED — static]

- Location: rust_backend/crates/mobile/src/native_lyrics.rs:468–472, parse_lrc.
- Scenario: crafted local MP3 embedded lyrics contain100,000 leading [00:01] timestamps plus4MiB trailing text (under5MiB input); parser attempts approximately390GiB independent text allocations before serialization.
- Root cause: clones full trailing text and word vector once per timestamp without cumulative output bound.
- Impact: crafted local metadata can terminate app through memory exhaustion.
- Fix: cap cumulative expanded output/text/words; check cancellation inside timestamp expansion.
- Evidence: times captures all prefixes;447–452 derives common clean text;453–476 clones it per timestamp; execute133–155 has no output cap. PlayerMetadataController19 defaults parseAsyncNative and116–137 forwards metadata lyrics; parser225–240 sends native bytes; data_jobs69 dispatches directly. Payload below32MiB selected ID3 frame cap.
- Cross-refs: data_jobs.rs,tags/id3.rs,lyrics_parser.dart,player_metadata_controller.dart.
- Guards checked: input/frame caps do not bound expansion; cancellation per source line does not interrupt inner loop; usable-timing validation happens after allocation. Native worker shares app process. Coordinator independently reread410–480/125–160 and Dart209–245; huge payload was deliberately not executed.

## Verification / limits

Coordinator ran `cargo test --manifest-path rust_backend/Cargo.toml --offline --locked -p spotiflac-mobile native_lyrics -- --nocapture`: PASS6,0 failed/ignored,90 filtered; host unit tests, no Android/device or engine tests executed. Includes shared parser goldens and cancellation/depth guards; passing suite does not cover expansion trigger. No Clippy/full workspace gate or crafted-file run.

No unsafe-memory claim. TTML depth guard/iterative traversal checked; descriptor duplicate owns copied descriptor, Kotlin owner lifetime not rereviewed. ID3 UTF16 surrogate-unit replacement explicitly marked legacy compatibility, retained as unresolved contract boundary rather than new finding. Writers/decoders excluded. Result FINDINGS, one P2; RUST-01-B separate.
