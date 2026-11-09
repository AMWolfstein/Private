# Findings 002: Media3 playback comparison and migration

Status: author source comparison/self-review only; no independent design round has
been run or recorded. Independent review remains open before implementation.

## Adaptation findings recorded in the roadmap

- Reference queue truncation/deduplication can change the requested song; target
  characterization and identity-preserving adaptation required before reuse.
- Reference PCM DSD/crossfade/output switcher do not establish direct USB/AutoMix/Cast parity.
- FFmpeg has non-playback consumers; engine replacement alone cannot justify deletion.
- Reference metadata reader and some analysis/scanner integration are not full replacements
  for target read/write/source behavior. Native removal and device/performance gates remain open.
- Historical migration authority is summarized in a guide, while the named original document
  is absent; policy reconciliation is explicitly not fabricated in this batch.

These are planning constraints, not new regressions introduced into the application.
