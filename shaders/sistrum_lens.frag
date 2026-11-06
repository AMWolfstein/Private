// Sistrum-owned lens for Sistrum Hybrid, the Full tier of the developer-only
// Glass POC. Written for this repository; it reuses no third-party shader.
//
// Used as `ImageFilter.shader` inside a `BackdropFilter`, so the sampler is the
// backdrop that Flutter has already read (after any blur in the same filter
// chain). Impeller only; the Dart side checks ImageFilter.isShaderFilterSupported.
//
// Coordinate space (verified in the engine source): FlutterFragCoord() and the
// filter's input texture are both in physical pixels, and the engine writes the
// input texture size into uniform 0 (uSize). The sampler takes normalized
// coordinates, so the lookup is FragCoord / uSize. Every length uniform below
// (uRadius, uBand) is therefore in physical pixels; the Dart side scales the
// logical values by the device pixel ratio.
#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;        // input size in physical pixels (set by the engine)
uniform float uRadius;     // corner radius, physical pixels
uniform float uBand;       // width of the refracting rim, physical pixels
uniform float uRefraction; // 0..1: strength of the rim displacement
uniform float uDispersion; // 0..1: colour split at the rim; 0 = none
uniform sampler2D uBackdrop;

out vec4 fragColor;

// Signed distance to the rounded rectangle that fills uSize: negative inside,
// zero on the outline. Pill shapes work because the radius is clamped to half
// the shorter side.
float roundedSdf(vec2 p) {
    vec2 halfSize = uSize * 0.5;
    float r = clamp(uRadius, 0.0, min(halfSize.x, halfSize.y));
    vec2 q = abs(p - halfSize) - (halfSize - vec2(r));
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void main() {
    vec2 p = FlutterFragCoord().xy;
    float depth = -roundedSdf(p);               // distance in from the outline

    // Lens profile: strongest on the outline, fading to zero across the band.
    float band = max(uBand, 1.0);
    float rim = 1.0 - smoothstep(0.0, band, depth);
    rim *= rim;

    // Outward normal from central differences of the SDF.
    vec2 e = vec2(0.5, 0.0);
    vec2 grad = vec2(
        roundedSdf(p + e.xy) - roundedSdf(p - e.xy),
        roundedSdf(p + e.yx) - roundedSdf(p - e.yx));
    vec2 normal = grad / max(length(grad), 1e-4);

    // Refraction: sample from further inside, along the normal, so the rim
    // pulls the backdrop toward the centre. Shift is in physical pixels.
    float shift = uRefraction * band * 0.5 * rim;
    float k = 0.5 * uDispersion;
    vec2 sampleG = clamp(p - normal * shift, vec2(0.0), uSize) / uSize;
    vec4 c = texture(uBackdrop, sampleG);
    if (uDispersion > 0.0) {
        // Red and blue sample slightly further and nearer than green.
        vec2 sampleR = clamp(p - normal * shift * (1.0 + k), vec2(0.0), uSize) / uSize;
        vec2 sampleB = clamp(p - normal * shift * (1.0 - k), vec2(0.0), uSize) / uSize;
        c.r = texture(uBackdrop, sampleR).r;
        c.b = texture(uBackdrop, sampleB).b;
    }
    fragColor = c;
}
