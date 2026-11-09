# Upstream test provenance

`apple_artist_artwork.test.cjs` and `apple_lyrics_unsynced.test.cjs` are copied
verbatim from https://github.com/mornyeapp/Mornye-Extension at
`12530ceda46dc78a10f9258b7d65a71452dfcf50`, under the licenses in the parent directory.
They test the retained upstream functions directly with mocked API data.

`source_import.test.cjs` is local and verifies the selected import boundary,
dependency completeness, hashes and restricted artwork adapters.
