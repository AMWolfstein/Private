# Selected internal extension sources

This directory stages source code for artist portraits, motion artwork and lyrics
from Mornye-Extension. **The application does not load these files.** Its existing
extension settings, store, network features, native lyrics providers and player
are unchanged. The JavaScript import itself neither installs executable packages nor activates those sources.

## Native Rust + JSON migration

`config/` now contains the bounded native lyrics configuration and schema. The
Backend reads bundled defaults and can load verified cached settings on restart.
A backend-owned signed-JSON updater and the initial application public signing key
are now integrated through Android readiness. Native artwork and local identity
integration are **not yet complete**; see [config/README.md](config/README.md) for exact limits. The JavaScript
source subsets below remain inactive reference code.

## Included code

- Artist-artwork dependency subsets from Amazon, Apple Music, Beatport, Bugs Music,
  Deezer, Genie Music, JioSaavn, Melon Music, Qobuz, SoundCloud, Spotify, Tidal and
  YouTube Music (13 providers).
- Apple's artist/album motion artwork, editorial images and artist logo handling.
- Apple's lyrics fetching and TTML conversion, including word/line timing,
  translations and pronunciation where the upstream service provides them.
- Existing initialization, cleanup, request, authentication, matching, formatting
  and cache helpers needed by those operations.

**Jellyfin is excluded at the owner's request.** The Python-only utilities package,
original installable packages, upstream registry, icons and store are not imported.
The application's built-in Rust lyrics providers remain unchanged. Separate source ports now live under `lyrics/`; they are not activated.

Each `sources/<provider>/index.js` registers only `getArtistArtwork`, optional
`initialize`/`cleanup`, and (Apple only) `getAlbumArtwork`/`fetchLyrics`. The artwork
adapter returns identity and image/video fields, dropping catalog lists from
successful results. It does not expose music download, preview, general search,
URL import or home-feed entry points. Original provider IDs are needed for artwork
lookups; resolving a local artist/album to those IDs is a future integration task.

The original artist/album lookup helpers can still request catalog pages, top songs
or concerts internally before the adapter discards them. These shared dependencies
are retained to avoid silently rewriting upstream behavior during source import.
An artwork-only network contract, host permissions and any request minimization
must be reviewed before activating these sources. Export filtering alone is **not**
a runtime sandbox or a guarantee that only artwork requests occur.

## Layout

- `sources/`: selected upstream JavaScript declarations, a limited registration adapter and `source.json`.
- `lyrics/`: staged JavaScript ports of the 14 native lyrics providers, with original Rust retained; see its README and draft host contract.
- `upstream-lock.json`: exact upstream commit, provider versions and hashes.
- `tools/`: development-only reproducible AST extraction tools; no application dependency.
- `tests/`: offline upstream artwork/lyrics tests and import/dependency/adapter checks.
- `LICENSE`, `COPYING`, `NOTICE`: upstream redistribution terms and attribution.
- `UPSTREAM.md`: import provenance, exclusions and update procedure.
- `updates/`: fortnightly upstream review scripts, tests and an inactive GitHub Actions template. All files stay inside this directory tree; activation requires the documented GitHub workflow-path exception.

`source.json` is **not** an installable extension manifest. Its `upstream_permissions`
and `upstream_settings` describe the original provider for later dependency review;
they do not grant permissions, configure the application or approve those settings
for a future internal source system. Original upstream version numbers do not imply
wire compatibility of these restricted source subsets with the current loader.

## Verify the import

Use Node.js 22 or newer and npm. Parser packages are development-only and pinned.
From the application repository root:

```sh
npm ci --prefix extensions/tools
NODE_PATH="$PWD/extensions/tools/node_modules" node --test extensions/tests/*.test.cjs
```

These tests use fixtures and mocked host services, with no requests to music services.
They verify syntax/loading, declaration dependency closure, allowed registrations,
checksums, portrait/motion selection and lyrics timing. They do not establish live
provider availability, complete authentication flows or device/player behavior.

## Integration still required

To make this an internal source system, the application needs a restricted loader,
artist/album matching from local metadata, bundled initial sources, approved host
APIs/permissions, cache integration, and separately signed compatible source updates
with rollback. No update endpoint, signing key, registry URL or CI publication is
configured by this import. Existing app updates and Google Cast are untouched.

Apple lyrics retain the original Media User Token/subscription requirement. Other
providers retain their original host/API/session requirements; copying their code
does not remove authentication requirements or guarantee results for every artist.
