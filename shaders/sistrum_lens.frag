// Sistrum-owned lens for Sistrum Hybrid, the Full tier of the developer-only
// Glass POC. Written for this repository; it reuses no third-party shader.
//
// Used as `ImageFilter.shader` inside a `BackdropFilter`, so the sampler is the
// backdrop that Flutter has already read (after any blur in the same filter
// chain). Impeller only; the Dart side checks ImageFilter.isShaderFilterSupported.
#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;        // surface size in logical pixels
uniform float uRefraction; // 0..1: how far the rim pulls the backdrop inward
uniform float uDispersion; // 0..1: colour split at the rim; 0 = none
uniform sampler2D uBackdrop;

out vec4 fragColor;

void main() {
    vec2 uv = FlutterFragCoord().xy / uSize;
    vec2 p = uv * 2.0 - 1.0;                         // centred, -1..1
    // Rim weight: zero across the middle, rising toward the edges.
    float rim = smoothstep(0.45, 1.0, max(abs(p.x), abs(p.y)));
    vec2 shift = -p * rim * uRefraction * 0.08;      // in uv units

    vec2 g = clamp(uv + shift, 0.0, 1.0);
    vec4 c = texture(uBackdrop, g);
    if (uDispersion > 0.0) {
        vec2 r = clamp(uv + shift * (1.0 + 0.5 * uDispersion), 0.0, 1.0);
        vec2 b = clamp(uv + shift * (1.0 - 0.5 * uDispersion), 0.0, 1.0);
        c.r = texture(uBackdrop, r).r;
        c.b = texture(uBackdrop, b).b;
    }
    fragColor = c;
}
