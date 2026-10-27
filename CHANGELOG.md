# Changelog

> Identity normalization (T16, 2026-10-28): historical names, paths and command strings below were mechanically renamed. Original evidence used the former terms; no listed checks were rerun by this rename. Encoded upstream/download identifiers retain their actual destinations.

## Local/offline migration

- Android-only player with local library, playback, playlists, metadata/lyrics editing,
  backups, SAF/USB support and launcher widgets retained.
- Removed online providers, extension runtime/store, download engine, network storage,
  updater, remote configuration, Discord and non-Android targets.
- Reduced Rust to core/local/mobile/bindgen; removed native credentials and network APIs.
- Consolidated app appearance on Sistrum; removed provider-specific settings, remote artwork
  requests, unused dependencies and unused translations. Release Internet permission removed.

See `LOCAL_OFFLINE_MIGRATION_PLAN.md` for phase commits and validation results. This fork's
history before the migration is available in Git; upstream release notes describe the
original online application and do not describe this player's capabilities.
