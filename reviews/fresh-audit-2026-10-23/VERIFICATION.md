# Fresh-audit verification

> Identity normalization (T16, 2026-10-28): historical names, paths and command strings below were mechanically renamed. Original evidence used the former terms; no listed checks were rerun by this rename. Encoded upstream/download identifiers retain their actual destinations.

Application baseline: `d5d5a02ecdad86dca50a4448cf7810b7eec43ad9`; later review commits do not modify app source. Device execution NOT RUN. No APK build requested/executed. Audio-engine tests excluded.

| Check | Result | Evidence / limits |
|---|---|---|
| Python helper tests | PASS, 28 tests | `python3 -m unittest discover -s scripts -p 'test_*.py' -v`, exit 0; `/tmp/fresh-audit-python.log` |
| Rust core tag unit tests | PASS, 14 tests | `cargo test --manifest-path rust_backend/Cargo.toml -p sistrum-core --locked tags::`, exit 0; 16 other unit tests and all filtered integration tests did not run; `/tmp/fresh-audit-rust-tags.log` |
| Direct ID3v2.4 extended-header reproduction | DEFECT REPRODUCED | `rewrite_audio_tags` returned `Ok(())`, removed untouched original artist, retained audio tail |
| Direct oversized invalid FLAC-cover replacement | DEFECT REPRODUCED | `rewrite_audio_tags` returned `Ok(())`, original cover absent after replacement |
| Flutter analyzer/test execution | BLOCKED | Flutter absent; official download host CONNECT denied 403. No Flutter test passes claimed |
| Android/SAF provider failure injection | NOT RUN | Static caller/writer traces only; device/provider required for end-to-end recoverability |
| Rust local library tests | PASS,20 tests | `cargo test --manifest-path rust_backend/Cargo.toml -p sistrum-local --locked`, exit0; doc tests0; `/tmp/fresh-audit-rust-local.log` |
| Physical #track filename incremental scan | DEFECT REPRODUCED | actual Backend API: existing_song=true, deletedPaths contains physical song, scanned=[], skipped=1; reproductions/local_scan.rs |

After a configuration/runtime reattachment, Flutter download was retried once following that state change and still returned403. Runtime tests remain blocked; no readiness inferred from the desired domain setting.

## Reproduction commands

The checked-in harness calls the actual current Rust core library. It constructs disposable in-memory tag files and uses an existing image fixture; it writes no user music. The ID3 fixture tests the tag rewriter independently of MP3 decoding. The small FLAC metadata fixture similarly targets tag handling, not decoding.

```bash
cd /workspace/Private-audit
source /workspace/toolchains/activate.sh
cargo test --manifest-path rust_backend/Cargo.toml -p sistrum-core --locked tags::
core_lib=$(find rust_backend/target/debug/deps -name 'libsistrum_core-*.rlib' -print -quit)
rustc --edition=2024 reviews/fresh-audit-2026-10-23/reproductions/tag_writer.rs \
  -L dependency=rust_backend/target/debug/deps --extern "sistrum_core=$core_lib" \
  -o /tmp/fresh-audit-tag-repro
/tmp/fresh-audit-tag-repro
```

Observed output:

```text
ID3v2.4 rewrite=Ok(()); original_artist_preserved=false; audio_tail_preserved=true
FLAC invalid large cover rewrite=Ok(()); original_cover_preserved=false
```

The normal tag unit suite passing does not invalidate the concrete missing edge cases.

## Local resume at 5dcf7241

Build-script tests: `python3 -m unittest discover -s scripts -p 'test_build_android.py' -v`, PASS 5, zero failures/skips. Full Python helpers: `python3 -m unittest discover -s scripts -p 'test_*.py' -v`, PASS 28, zero failures/skips. These use fixture tools/archives and do not build the application. Scope build and coverage-status commands exit 0; historical build coverage stale, graph fresh from46c4ea6a. Flutter absent from PATH here; no new analyzer, Flutter, native, APK or device result. See08-build-dependencies.md for limits.

## UI and native-contract continuation

Reports09–11: six additional P2 findings validated statically; native backup contract gap closed with no new finding (DATA-007 duplicate confirmed). Source/fixture ledgers in each report. No additional runtime tests, builds or device execution. Application-source diff from d5d5a02 remains empty. Push of d3a25128 failed because GitHub HTTPS credentials were unavailable; local reports/commits retained.

## Overall continuation through reports12–21

`cargo test --manifest-path rust_backend/Cargo.toml --offline --locked -p sistrum-mobile native_lyrics -- --nocapture`: PASS6 host unit tests,0 failures/ignored,90 filtered. No engine tests/device execution; no enormous crafted payload executed. Static findings and exact read ledgers in reports12–21. Application source unchanged from d5d5a02; only reviews files queued. Flutter unavailable; no analyzer/full Flutter gate or APK. Security path proof static only.
