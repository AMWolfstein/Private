# Native provider configuration and provenance

Provider execution stays in Rust. `config/` contains signed, bounded JSON settings
and documentation for independent settings updates. All fourteen native lyric
implementations remain active and unchanged by the JavaScript cleanup.

The unused JavaScript source imports, CommonJS lyric ports, draft JavaScript host
contract, extraction dependencies and their JavaScript-only tests have been removed.
They were never loaded by the application. The application's existing installed
extension system is retained: native artwork is not ready to replace it.

## Layout

- `config/`: signed settings, trusted public keys, schema and implementation report.
- `artwork/`: native-port golden fixtures and migration status; Rust codecs/clients
  live under `rust_backend/crates/providers/src/artwork/`.
- `lyrics/origin-lock.json`: original native lyric provenance, not a JS package.
- `upstream-lock.json`: historical upstream versions and hashes from the former
  import, retained for native port attribution and review.
- `updates/`: Python-only fortnightly upstream review tooling and an inactive
  GitHub Actions template. Proposals require manual review; no automatic merge.
- `UPSTREAM.md`, `NOTICE`, `LICENSE`, `COPYING`: provenance and redistribution terms.

Apple/Deezer artwork codecs and HTTP clients remain **inactive foundations**:
app callers, artwork JSON settings, remaining sources and full parity are pending.
Jellyfin is excluded. Playback, Google Cast and application updates are unchanged.

## Checks

```sh
python3 -m unittest discover -s extensions/updates/tests -v
cargo +1.99.1 test --manifest-path rust_backend/Cargo.toml -p mornye-providers --locked
```

Signed settings still use the established `extension-system` publication URL.
This consolidation does not change the updater's trust root, private-key ownership
or restart-only activation. A new algorithm or network permission still needs an
application update; JSON does not execute provider code.
