# Upstream backport backlog

All approved PORT_PLAN batches 1, 1b and 2–16 are complete. Exact source → graph → docs checkpoints, including test-fixture follow-ups, are in [PORT_EXECUTION.md](PORT_EXECUTION.md). No implementation batch remains queued.

| Priority | Next work | Status / boundary |
|---|---|---|
| 1 | Physical Android verification: SAF scan/edit/lyrics/CUE, playback retry, both player views/rotation/queue, EQ and haptics | NOT RUN; requires a device. No APK requested or built in this batch. |
| 2 | DATA-501 and KT-202 plus remaining review findings | OPEN; separate FIX_PLAN scope, not silently folded into upstream ports. |
| 3 | DEAD-806 legacy bookmark fields and iOS path normalization | Partial cleanup; compatibility/on-open hook retained. Decide separately before further removal. |
| 4 | Existing material_ui transitive dependency from go_router 18.0.2 | Direct declaration/imports removed; router replacement is an unapproved architectural change. |
| 5 | DEAD-702 artist tag mode / old settings plumbing | Still live in metadata/import paths; not assigned to Tier 3 rows. Changing persisted/import semantics requires separate review. |
| — | Material Expressive, online providers/downloads/lyrics, greeting/On Repeat, crash reports on Home | REJECT. Do not restore. |
| — | Media3/ExoPlayer, Sistrum and replacement Rust DSP architecture | DEFER to the future project phase. |

No blocked adoption is represented as complete. Retained compatibility code and owner exceptions are listed in the final report and Batch 16 disposition notes.
