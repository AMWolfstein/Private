# Native artwork migration

Reference: Mornye-Extension `12530ceda46dc78a10f9258b7d65a71452dfcf50`.
The current tree retains native code, golden fixtures and upstream attribution;
the unused local JavaScript references and oracle have been removed.

```sh
cargo +1.99.1 test --manifest-path rust_backend/Cargo.toml -p mornye-providers artwork --locked
```

Twenty fixtures cover Apple artist/album still, motion, logo and album editorial
fields, and Deezer artist image selection. They were verified against the pinned
JavaScript before removal. To reproduce the oracle, use a separate checkout of
`cb7c06e14f38730306da7010af991f6474f6f0df` from the preserved `extension-system`
branch and run `node extensions/artwork/tools/reference-fixtures.cjs` there.
The current Rust tests consume the committed fixture snapshot directly and do not
require Node, copied JavaScript or extraction dependencies.

## Current implementation boundary

Native codecs and on-demand HTTP clients exist in
`rust_backend/crates/providers/src/artwork/` for:

- Apple Music: artist artwork and album artwork/editorial fields.
- Deezer: artist artwork.

HTTP clients use separate domain-restricted sessions, a shared 30-second lookup
budget, an 8 MiB response limit, cancellation and identity validation. Apple token
discovery follows its artwork reference's music.apple.com page/bundle strategies,
not the different beta.music.apple.com strategy used by the lyric implementation.
A catalog 401 refreshes the token once. Artwork requests omit discography,
concerts and track pagination; existing catalog APIs remain untouched.

These clients are **not yet connected to application callers or signed JSON
settings**. They do not replace the installed-extension metadata path. The native
configuration updater's schema 1 still controls only lyric origins. None of the
13 artwork sources is counted as a completed end-to-end migration yet.

Pending: authenticated settings schema, app caller/cache-generation integration,
remaining eleven source-specific native implementations, retry/cache parity,
HTTP integration tests, and final review. No claim of device testing or full
source parity follows from the offline fixtures or scripted transport tests.
Jellyfin remains excluded; all fourteen native lyric implementations are retained.
