// Edge-only refraction for the Sistrum Hybrid shared backdrop atlas (developer
// POC only). Written for this repository; it reuses no third-party shader.
//
// Drawn as a paint shader over the rim ring of a surface, not inside a
// BackdropFilter: it samples the atlas texture that the same frame already
// captured, so it adds no backdrop read. The centre of the surface is not
// drawn with this shader.
//
// The rim profile matches sistrum_lens.frag: the displacement is zero at the
// inner edge of the band, so the ring meets the undistorted centre without a
// seam.
//
// Coordinates: FlutterFragCoord() is the geometry's local position in the
// canvas units of the draw (logical px here), so it is shifted by uOrigin to
// the surface. Atlas lookups map a surface point to texture pixels with
// uAtlasOrigin and uScale (atlas px per logical px), clamped to the surface so
// no neighbouring atlas slot is read.
#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;        // surface size, logical px
uniform float uRadius;     // corner radius, logical px
uniform float uBand;       // rim width, logical px
uniform float uRefraction; // 0..1: strength of the rim displacement
uniform float uDispersion; // 0 or 1: colour split at the rim
uniform vec2 uOrigin;      // surface top-left, canvas units (logical px)
uniform vec2 uAtlasOrigin; // surface top-left in the atlas, texture px
uniform float uScale;      // atlas px per logical px
uniform vec2 uAtlasSize;   // atlas texture size, texture px
uniform sampler2D uAtlas;

out vec4 fragColor;

// Signed distance to the rounded rectangle that fills uSize: negative inside.
float roundedSdf(vec2 p) {
    vec2 halfSize = uSize * 0.5;
    float r = clamp(uRadius, 0.0, min(halfSize.x, halfSize.y));
    vec2 q = abs(p - halfSize) - (halfSize - vec2(r));
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

// Atlas sample for a point of the surface, clamped to the surface.
vec4 atlasAt(vec2 q) {
    vec2 c = clamp(q, vec2(0.0), uSize);
    return texture(uAtlas, (uAtlasOrigin + c * uScale) / uAtlasSize);
}

void main() {
    vec2 p = FlutterFragCoord().xy - uOrigin;
    float depth = -roundedSdf(p);

    float band = max(uBand, 1.0);
    float rim = 1.0 - smoothstep(0.0, band, depth);
    rim *= rim;

    vec2 e = vec2(0.5, 0.0);
    vec2 grad = vec2(
        roundedSdf(p + e.xy) - roundedSdf(p - e.xy),
        roundedSdf(p + e.yx) - roundedSdf(p - e.yx));
    vec2 normal = grad / max(length(grad), 1e-4);

    float shift = uRefraction * band * 0.5 * rim;
    float k = 0.5 * uDispersion;
    vec4 c = atlasAt(p - normal * shift);
    if (uDispersion > 0.0) {
        c.r = atlasAt(p - normal * shift * (1.0 + k)).r;
        c.b = atlasAt(p - normal * shift * (1.0 - k)).b;
    }
    fragColor = c;
}
