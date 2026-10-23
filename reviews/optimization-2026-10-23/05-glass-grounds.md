# Shared glass and ground rendering (U2)

## Scope

code-optimization-auditor, appd5d5a02 unchanged/baseline968fbe57. Complete reads under lib/widgets/: mornye_chrome.dart1–732,mornye_liquid_backdrop.dart1–123,mornye_backdrop_groups.dart1–371,mornye_glass_preparation.dart1–41,mornye_glass_auto_probe_host.dart1–106,mornye_artwork_glass.dart1–1220,mornye_player_ground.dart1–237,mornye_bottom_bar.dart1–369,mornye_glass_thumb.dart1–180,mornye_performance_hud.dart1–435. Ten files3,814lines, no supplements. Graph explain MornyeChromeBatch completed before reads.

## Findings

None established. Existing mechanisms checked: chrome batch membership/route-folding exclusions and renderer-gated blur keys; ground in-flight/input deduplication,384px decoding,dimension cap/global6MB ownership; render-side ground crossfade repaint; retained/disposed shader instances; no known-artwork backdrop sampling; latched overlay readiness; cached clarity filters/touch thumb release contraction. HUD300-frame/twice-second bounds and no callbacks while off; Auto callback only while measuring.

## Verification / limits

Static source review only, no raster capture,GPU memory/power profile,tests/builds/devices. Package shader/sampler implementations,shader assets and runtime-policy internals outside chunk. No suggestion to weaken required visual behavior or existing quality/batching/material gates. No edits/graph/security checks. Result PASS for bounded scope, no measured certification.
