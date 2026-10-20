# Upstream port handoff

Current phase: batch 5 complete; stop before batch 6.
Branch/repository: `ccr-2fb644cd-nmesyt`, `/workspace/Private`.
Entry checkpoint `6df45c62`; remote fetched/equal and working tree clean at start.
Read-only upstream clone `/workspace/mornye-upstream` at `e0563ffa`.
Baseline v5.1.1 `78699a91`; use PORT_PLAN for current batch order.

Batch 5 source → graph:
- U-214 upstream `d7798898e1036b30240326817a1b6e0e684db0e3`:
  `10c04f7a` → `3a5cca2a`. ADAPT Activity attachment wait before local Android startup
  channels; lifecycle tests retained. No extension/crash initialization.
- U-215 upstream `205e178e5b7df779094b7ba829eac0e141678d74`:
  `fa838caa` → `a88e3696`. ADAPT inline renderer rules into a shared helper (prior rules
  verified identical); minimal SpotiFlacApplication registered in manifest sets audio_service
  arguments before shared Flutter engine creation. Defensive copy / reject late setter;
  narrowly scoped Android 15 Xiaomi model workaround and two policy tests. No crash reporter.
  third_party/audio_service/SPOTIFLAC_PATCHES.md records this source in the docs checkpoint.
- U-208 upstream `47ccf9c9ede4dcf53050fcd272fcaa2108229780`: REJECT Material-only
  AppSlider thumb sizing. Those files are absent; MornyeVolumeControl uses the intentionally
  thumb-free MornyePlayerSlider (6px track). No source port.
- U-209 `acbc614f422809b5eb586ca5d9ef2848678025cb`:
  `ba751b35` → `ffbafbe1`. ADOPT constant lyric-alignment regex reuse only.
  Removed online album/metadata hunks REJECT. DEFER audio_info_sheet number-pattern hunk
  to U-303 batch 6; locale-cached DateFormat/letter patterns to U-305 queue sections batch 8.
- U-209 `ef5fa1cb4607a6ff30438ec2f0d163cf7e35fe50`:
  `2c4ce3ff` → `11d8f750`. ADOPT local native lyrics LazyLock credit regex reuse with
  identical patterns. Provider/source names here only parse stored text; no provider/network
  integration added. Existing shared native/Dart goldens cover credits and pronunciation
  widget tests cover retained alignment. Download extension hunk REJECT.
- U-209 `1b66bc469db62f09dedefebae2cf2858e97aeec7`: REJECT removed download-history
  notifier and its tests. Do not restore that provider just for an optimization.
- Graph source `2c4ce3fff4aff255c8c4b200fa9580adca0a900e`, graph commit `11d8f750`:
  23,147 unique nodes / 44,693 valid links. Existing vendor extraction warnings remain.
- No dependencies/schema changes, branding, removed features or replacement engine.
  No runtime performance claim. KT-202 remains OPEN, unrelated to this batch.

Batch 5 verification: PASS: analysis clean; full Flutter 1,659 passed / 3 skipped / zero failures (4m02s); Rust fmt/Clippy clean, 231 passed / 1 ignored; Android unit 61 passed / 1 skipped (1m06s).
Android manifest resolves com.zarz.spotiflac.SpotiFlacApplication; all 396 dry-run tasks
checked for absence of APK/AAB packaging or assemble tasks (resource/JAR tasks are allowed).
Physical-device startup from media service, Activity recreation and actual GPU rendering
NOT RUN. Tests of policy/compilation do not prove physical device crash recovery.
Logs /workspace/batch-5-analyze.log, batch-5-full-tests.log, batch-5-rust.log,
batch-5-kotlin.log, batch-5-gradle-dry-run.log and batch-5-*-graphify.log.
Exit files batch-5-flutter.exit, batch-5-rust.exit, batch-5-kotlin.exit.
Push status: this docs checkpoint is committed/pushed after validation; final remote equality
must be checked in session output. On resume fetch and compare remote before editing.
Latest docs SHA: `git log -1 --format=%H -- reviews/HANDOFF.md`.

Next exact work unit, only when requested: batch 6 — U-210, U-303, U-217, U-218.
Read AGENTS, STATE, PORT_PLAN, UPSTREAM; status/branch/checkpoint, Graphify before edits.
U-210: album_detail_header part only. U-303: include deferred U-209 audio_info_sheet
number regex. U-217: preserve mini-player dismissal (UI-101). U-218: retain ReplayGain.
One code → graph checkpoint per logical port; checks once at batch end, docs, push/fetch.
No APK, branding, Material, online, replacement engine or premature later batches.

Model policy SOL only; identity and runtime effort not exposed, no model switch.
Continued user MEDIUM preference; recommended next effort MEDIUM unless evidence requires
escalation. Activate /workspace/toolchains/activate.sh; Graphify at
/workspace/toolchains/graphify/bin/graphify. Existing cloud setup reused unchanged.
