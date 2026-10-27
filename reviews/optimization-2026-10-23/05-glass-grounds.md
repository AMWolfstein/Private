# Shared glass and ground rendering (U2)

> Identity normalization (T16, 2026-10-28): historical names, paths and command strings below were mechanically renamed. Original evidence used the former terms; no listed checks were rerun by this rename. Encoded upstream/download identifiers retain their actual destinations.

## Scope

code-optimization-auditor, appd5d5a02 unchanged/baseline968fbe57. Complete reads under lib/widgets/: sistrum_chrome.dart1–732,sistrum_liquid_backdrop.dart1–123,sistrum_backdrop_groups.dart1–371,sistrum_glass_preparation.dart1–41,sistrum_glass_auto_probe_host.dart1–106,sistrum_artwork_glass.dart1–1220,sistrum_player_ground.dart1–237,sistrum_bottom_bar.dart1–369,sistrum_glass_thumb.dart1–180,sistrum_performance_hud.dart1–435. Ten files3,814lines, no supplements. Graph explain SistrumChromeBatch completed before reads.

## Findings

None established. Existing mechanisms checked: chrome batch membership/route-folding exclusions and renderer-gated blur keys; ground in-flight/input deduplication,384px decoding,dimension cap/global6MB ownership; render-side ground crossfade repaint; retained/disposed shader instances; no known-artwork backdrop sampling; latched overlay readiness; cached clarity filters/touch thumb release contraction. HUD300-frame/twice-second bounds and no callbacks while off; Auto callback only while measuring.

## Verification / limits

Static source review only, no raster capture,GPU memory/power profile,tests/builds/devices. Package shader/sampler implementations,shader assets and runtime-policy internals outside chunk. No suggestion to weaken required visual behavior or existing quality/batching/material gates. No edits/graph/security checks. Result PASS for bounded scope, no measured certification.
