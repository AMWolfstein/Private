# Runtime budgets,shader assets and build/tooling triage (R1)

## Scope

Coordinator code-optimization-auditor, unchanged appd5d5a02/baseline968fbe57. Focused supplement: lib/main.dart runtime-budget/cache/Auto/migration markers and prior unchanged startup reads; both assets/shaders/*.frag complete; pubspec.yaml,Cargo.toml,Android Gradle/build scripts candidate-screened using prior immutable build reads plus minify/shrink,LTO,incremental input/output and debug-info markers. Scripts/tests/config/localization/assets inventoried for hot-path relevance,not all cold bodies expanded. Graph initial performance/bounded-cache query and A1 explanation supplied navigation.

## Findings

None established. Runtime image-cache budgets device-class bounded(24/60/80MiB) with entry limits; source1main306–350 applies caps. Shaders use fixed per-fragment arithmetic/sampling with no unbounded loops; shader-off/lite/touch gates separately verified U2/U4. Rendering cost requires GPU capture and existing visual/parity constraints; no speculative shader simplification promoted. Release minify/resource shrink,split debug info,Rust thinLTO/codegen unit and Gradle declared inputs/outputs observed. No build-time/runtime speedup asserted from flags alone.

## Verification / limits

No APK/compiler/profiler/power/size or build-cache benchmark. Tests/benchmarks/manual scripts are measurement tools or cold developer paths,not evidence of application bottlenecks; no one-off setup/config micro-optimizations suggested. Upstream vendor bodies/public platform APIs and legacy playback migration boundary retained. No security/dead-code audit/changes. Source diff from baseline empty outside reviews. Result PASS for bounded triage,not GPU/build performance certification.
