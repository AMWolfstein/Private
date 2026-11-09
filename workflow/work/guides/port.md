

Use the `spec` skill to record preserved behavior, approved differences and an evidence-backed disposition per component: reuse, adapt, restructure or exclude. A well-tested module can be reused without splitting. Keep owner-reported source device validation distinct from checks performed on the new integration; neither dismiss the former nor invent the latter. Link parity requirements to the tasks and checks that establish them.

1. Check the accepted spec's prerequisites. Select an explicit reference revision, destination and accepted mode. Record unavailable reference sources as blocked; never fabricate equivalence.
2. Inventory the old behavior, its consumers, regression tests, known defects and licence/attribution.
3. Define parity using `workflow/work/guides/contracts/data-compatibility.md` and playback contracts. Port meaningful tests/fixtures before risky implementation. Run old/new against common input where possible. Record intentional differences instead of making buggy output the oracle.
4. Place implementation in the target responsibility boundary. Transfer actual fixes and errors, not arbitrary file splits or old global dependencies. Keep pure codecs/DSP separate from Android adapters.
5. Run differential and failure tests; record tolerances for analysis and byte-exact cases for identity/tag/PCM contracts. Validate cancellation and publication end to end; coroutine cancellation alone does not prove interruption of blocking I/O.
6. Switch consumers only after the replacement's acceptance criteria pass. Remove obsolete code/resources/settings/tests only with a reference inventory and proof that retained features work. Device checks remain independent gates.
7. Record provenance, evidence, and pending device behavior.
