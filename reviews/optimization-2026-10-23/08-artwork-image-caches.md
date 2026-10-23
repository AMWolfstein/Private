# Artwork/image cache and palette pipeline (A1)

## Scope

Coordinator as code-optimization-auditor, appd5d5a02 unchanged. Six paths1,899lines: lib/widgets/cached_cover_image.dart1–297,theme/cover_palette.dart1–425,services/cover_analysis_store.dart1–91,utils/image_cache_utils.dart1–12,playback_artwork.dart1–57,services/downloaded_embedded_cover_resolver.dart1–1017. Resolver full immutable read retained from prior lifecycle pass; hot scheduler/cache/maintenance ranges reviewed. Cached image/utils/store fresh complete reads; palette combined output truncated,subsequent1–265/245–340 reads cover key/sample/worker pipeline; builder retained immutable reads,not fresh whole-body certification. Ground1–220/graphics marker search was supplemental navigation; U2 owns complete grounds. Graph explain CachedCoverImage completed before inspection.

## Findings

None promoted. Existing behavior checked: bounded display-size/DPR thumbnail decoding and aspect-preserving target selection; palette112px sample,32 recent analyses,64schemes,in-flight sharing,versioned DB storage/4000row cap,worker/native quantization/analysis and one analysis source; resolver2 extraction workers,24background queue,180memory entries,384persistent/160MiB sweep bounds,source-version checks and foreground prioritization. Local artwork probes async,stale results checked in consuming screens.

## Verification / limits

No image-memory/IO/frame profile,tests/builds/devices. No measured cache-hit certification. Retention SQL/persistent-directory maintenance have bounded per-write costs but no material application bottleneck established,so no speculative cache/index redesign promoted. Known resolver correctness/dead-code findings not relabeled as optimization issues. Shared ground/glass implementation separately U2. No edits/graph/security checks. Result PASS for bounded static hot-path review.
