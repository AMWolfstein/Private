# Planned tasks — execution NOT authorized

One planning document commit only now. After later authorization each task uses:
map/context → implementation and checks → independent review/fixes(max3) → ONE commit.
The next task waits for that commit. Extras become TOR###. No T000: task start
already updates the map. No APK task due to explicit owner instruction.

- [ ] T001 Pin retained theme visual/interaction, preference migration and cold/headless bootstrap behavior before edits (FR-003, FR-004, FR-006, FR-007) — check: auto
- [ ] T002 Promote MornyeTheme to canonical AppTheme with explicit temporary legacy-builder collision handling; neutral core types/imports, no output change (FR-002, FR-003) — check: auto
- [ ] T003 Rename dedicated theme components/controllers/screens/runtime glass types, shader and associated tests with atomic part/import/asset updates (FR-002, FR-003, FR-007) — check: auto
- [ ] T004 Switch all startup/persistence/Appearance paths to the sole design and remove style/wallpaper choices while preserving retained stored settings (FR-001, FR-004, FR-006) — check: auto
- [ ] T005 Collapse alternate screen/control/player/notification branches to the retained design; remove selectors, legacy builder and obsolete layout wrappers (FR-001, FR-003, FR-005, FR-006) — check: auto
- [ ] T006 Remove proven Material-only dependencies/assets/strings/tests and finalize neutral design-system documentation/residual checks (FR-002, FR-005, FR-007) — check: auto
- [ ] T007 [AUDIT] Audit touched code/tests/gaps; fix only verified dead/redundant code and missing retained-behavior coverage (FR-005, FR-007) — check: auto
- [ ] T008 [FINAL] Check and independently review cumulative one-design/naming/persistence/behavior result; record device limitations (FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007) — check: auto android-unit
