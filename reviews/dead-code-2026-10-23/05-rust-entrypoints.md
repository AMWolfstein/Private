# Rust dead-code entrypoint review (N2)

## Scope

Role dead-code-hunter; source d5d5a02 unchanged. All78 tracked Rust files under rust_backend/crates filename-screened; all four Cargo manifests, core/local/mobile lib.rs module roots, bindgen main.rs and mobile/uniffi.toml read. Generic lexical function screen842 declarations; coordinator non-pub function census593 declarations across220 native code/build files:176 singletons, comprising168 #[test] roots and8 Serde Visitor trait callbacks (legacy.rs106,137,140,143,146,149,152,155). Coordinator independently read legacy95–162, module/bindgen roots and vendor README. Not AST/call-graph completeness.

Targeted reviewer reads: mobile/local.rs35–65,tags.rs65–82,208–235; cross-language refs for grant_directories,scan_cue_file_for_library_from_descriptor,write_m4a_freeform_tags across Android,lib,test,integration_test,scripts,third_party,crates. Graph native query completed truncated; used for navigation only.

## Findings

None validated. Rust-singleton public exports have Kotlin consumers: grantDirectories in SelectedCoreBackend80/180, scanCueFileForLibraryFromDescriptor273 and instrumentation, writeM4aFreeformTags319–320/MainActivity1029. UniFFI functions/public crate APIs remain entrypoints without Rust-local calls. Legacy Visitor methods have dispatch consumers in Serde; test function names are automatic runner roots.

## Verification / limits

Static reference and module/export screening, no compiler warning gate, linker map, build/test or size measurement. Engine included for lexical reachability, no behavioral/security review. Mutually unused islands, shared-name false positives and feature-conditional code can evade lexical census; no claim that every Rust line is necessary. Vendor bodies reviewed separately as retained upstream package interfaces. No edits. Result PASS for bounded candidate screen only.
