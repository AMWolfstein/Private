# Fresh-audit verification

Application baseline: `d5d5a02ecdad86dca50a4448cf7810b7eec43ad9`; later review commits do not modify app source. Device execution NOT RUN. No APK build requested/executed. Audio-engine tests excluded.

| Check | Result | Evidence / limits |
|---|---|---|
| Python helper tests | PASS, 28 tests | `python3 -m unittest discover -s scripts -p 'test_*.py' -v`, exit 0; `/tmp/fresh-audit-python.log` |
| Rust core tag unit tests | PASS, 14 tests | `cargo test --manifest-path rust_backend/Cargo.toml -p spotiflac-core --locked tags::`, exit 0; 16 other unit tests and all filtered integration tests did not run; `/tmp/fresh-audit-rust-tags.log` |
| Direct ID3v2.4 extended-header reproduction | DEFECT REPRODUCED | `rewrite_audio_tags` returned `Ok(())`, removed untouched original artist, retained audio tail |
| Direct oversized invalid FLAC-cover replacement | DEFECT REPRODUCED | `rewrite_audio_tags` returned `Ok(())`, original cover absent after replacement |
| Flutter analyzer/test execution | BLOCKED | Flutter absent; official download host CONNECT denied 403. No Flutter test passes claimed |
| Android/SAF provider failure injection | NOT RUN | Static caller/writer traces only; device/provider required for end-to-end recoverability |

## Reproduction commands

The checked-in harness calls the actual current Rust core library. It constructs disposable in-memory tag files and uses an existing image fixture; it writes no user music. The ID3 fixture tests the tag rewriter independently of MP3 decoding. The small FLAC metadata fixture similarly targets tag handling, not decoding.

```bash
cd /workspace/Private-audit
source /workspace/toolchains/activate.sh
cargo test --manifest-path rust_backend/Cargo.toml -p spotiflac-core --locked tags::
core_lib=$(find rust_backend/target/debug/deps -name 'libspotiflac_core-*.rlib' -print -quit)
rustc --edition=2024 reviews/fresh-audit-2026-10-23/reproductions/tag_writer.rs \
  -L dependency=rust_backend/target/debug/deps --extern "spotiflac_core=$core_lib" \
  -o /tmp/fresh-audit-tag-repro
/tmp/fresh-audit-tag-repro
```

Observed output:

```text
ID3v2.4 rewrite=Ok(()); original_artist_preserved=false; audio_tail_preserved=true
FLAC invalid large cover rewrite=Ok(()); original_cover_preserved=false
```

The normal tag unit suite passing does not invalidate the concrete missing edge cases.
