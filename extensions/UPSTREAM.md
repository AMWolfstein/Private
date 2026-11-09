# Upstream provenance and maintenance

Repository: https://github.com/mornyeapp/Mornye-Extension

Imported revision: `12530ceda46dc78a10f9258b7d65a71452dfcf50`.

Application branch at import: `extension-system`, based on
`60af01ad2f2af3e45287ebcd4ef0b906387f01c9` from `mornye-reboot3`.

## Extraction method

`tools/extract.cjs` parses the original JavaScript and resolves lexical references.
Starting from each provider's registered artist lookup and lifecycle functions,
and Apple's album/lyrics lookups, it retains their transitive top-level declaration
dependencies in original order. Beatport's outer IIFE is unwrapped within its own
provider source file. Original declaration text is preserved; full-provider
registration and unrelated top-level execution are excluded. A new adapter exposes
only artwork results and Apple's lyrics operation.

Each `source.json` records the original source SHA-256, exact source line spans,
retained declaration names, external global references, source version and extracted
SHA-256. `upstream-lock.json` inventories the complete selected import. Extraction
is static evidence, not proof of dynamically executed paths or production readiness.

## Inclusion and exclusion

All 13 source-backed JavaScript artist providers other than Jellyfin are retained.
Apple Music supplies the explicit editorial motion artwork implementation and the
only included extension lyrics implementation. Jellyfin's source and lyrics are
excluded explicitly, even though present upstream. Python-only utilities are not
an Android JavaScript provider and are excluded. Original `.sflx`/legacy packages,
store registry and unrelated entry points are not redistributed here.

Internal helpers may still contain shared catalog parsing/search and token/session
support needed by the retained functions. Their presence is not permission to
restore public catalog browsing, downloads or an extension store. See README.md
for the boundary between this source import and a future runtime implementation.

The later `lyrics/` directory is a separate port of this application's native Rust providers, not an additional import from Mornye-Extension; its origin and integration limitations are recorded there.

## Refreshing selected sources

1. Fetch the upstream repository separately and review changes affecting these
   providers. Keep the checkout clean and record the chosen full commit ID.
2. Compare provider source and license changes against the pinned revision above.
   K-Music (Bugs/Melon/Genie) carries an upstream README redistribution-permission
   explanation dated 2026-11-06; retain that provenance when refreshing those sources.
3. From this repository root, install the pinned development tools and regenerate:

   ```sh
   npm ci --prefix extensions/tools
   NODE_PATH="$PWD/extensions/tools/node_modules" node extensions/tools/extract.cjs /path/to/Mornye-Extension
   NODE_PATH="$PWD/extensions/tools/node_modules" node --test extensions/tests/*.test.cjs
   ```

4. Review the generated diff, especially dependencies, host globals, authentication,
   network hosts, settings and the absence of music-download entry points. Extraction
   must be reviewed when upstream changes its registration or declaration layout.
5. Update the pinned revision in this document and any affected fixtures; commit
   validated source and provenance. Upstream test copies are pinned separately in
   `tests/UPSTREAM.md`; review and update them explicitly, never overwrite local
   import/adapter tests just to match new upstream behavior.

Do not automatically publish every upstream change to users. The future application
source updater must only accept reviewed packages signed by the application owner's
source-update key, with compatibility checks and a previous-working-version fallback.
No such loader, signing or remote updater is implemented in this import.
