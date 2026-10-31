# Data and port compatibility

Before a port, record each invariant and its old/new test paths:
- Library song IDs and relationships to history, Loved and playlists.
- Schema versions, migrations, transaction/WAL behavior and SQLite feature availability.
- Old-backup restore and any promised forward compatibility; archive validation, size limits, traversal rejection and atomic publication.
- Cover cache keys and derived cover analysis; one owner of palette/HCT rules.
- Tag outputs, frame/padding policy, retained pictures/lyrics/ReplayGain; original file survives failed writes.
- CUE track numbering, boundaries/data-track handling; deleting a virtual row preserves backing media.

Run reference and new implementation on the same corpus. Compare exact bytes only where the contract requires them; numeric/audio analyses use documented justified tolerances. Never normalize away a real semantic difference. Keep known-bug corrections separate from parity decisions.

Test failures during reading, writing, flush, rename, database commit, permission loss and cancellation. Finishing a staging archive is not the final commit. Pre-cancellation may be intentional; do not remove it just because a registry entry has no active consumer.

Reference code, fixtures and licences must carry provenance. Host parser tests do not prove Android provider behavior. Mark device-only cases pending until executed.
