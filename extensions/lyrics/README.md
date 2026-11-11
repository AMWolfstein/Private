# Native lyric provenance

The fourteen active lyric providers remain in
`rust_backend/crates/providers/src/lyrics/`. Their original provenance is recorded
in `origin-lock.json`; endpoint configuration is under `extensions/config/`.

The unused CommonJS copies and draft JavaScript host were removed during the
Rust + JSON consolidation. No native provider implementation was deleted or
replaced. Historical copies remain in commit
`cb7c06e14f38730306da7010af991f6474f6f0df` on the preserved `extension-system` branch.
