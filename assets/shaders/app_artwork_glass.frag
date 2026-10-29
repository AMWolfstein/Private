#include <flutter/runtime_effect.glsl>

// Glass over a known, pre-blurred ground image (Sistrum's own; no backdrop
// read). Coordinates are the panel's local logical pixels; the panel and the
// ground are mapped through their screen rects. The clip, fill and rim are
// painted around this shader.

uniform vec2 uSize;        // panel size
uniform vec4 uPanel;       // panel rect on screen (x, y, w, h)
uniform vec4 uGround;      // ground image rect on screen
uniform float uRadius;     // corner radius
uniform float uSquircle;   // 1: continuous (squircle) corners
uniform float uBand;       // width of the bending edge band
uniform float uBend;       // displacement at the very edge
uniform float uDispersion; // widest colour split
uniform vec4 uEdge;        // colour outside the ground (premultiplied)
uniform float uMix;        // crossfade from uImage to uNext
uniform sampler2D uImage;
uniform sampler2D uNext;

out vec4 fragColor;

float shape(vec2 p) {
  vec2 half_size = uSize * 0.5;
  float r = min(uRadius, min(half_size.x, half_size.y));
  vec2 q = abs(p) - half_size + vec2(r);
  vec2 m = max(q, vec2(0.0));
  float corner = uSquircle > 0.5
      ? pow(pow(m.x, 4.0) + pow(m.y, 4.0), 0.25)
      : length(m);
  return corner + min(max(q.x, q.y), 0.0) - r;
}

vec4 ground(vec2 local) {
  vec2 screen = uPanel.xy + local * (uPanel.zw / uSize);
  vec2 uv = (screen - uGround.xy) / uGround.zw;
  if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
    return uEdge;
  }
  return mix(texture(uImage, uv), texture(uNext, uv), uMix);
}

void main() {
  vec2 local = FlutterFragCoord().xy;
  vec2 p = local - uSize * 0.5;
  float depth = max(-shape(p), 0.0);
  // 1 at the rim, 0 past the band: a convex edge bends the most.
  float edge = 1.0 - clamp(depth / max(uBand, 1.0), 0.0, 1.0);
  edge *= edge;
  vec2 e = vec2(0.5, 0.0);
  vec2 normal = vec2(
    shape(p + e.xy) - shape(p - e.xy),
    shape(p + e.yx) - shape(p - e.yx)
  );
  float len = length(normal);
  normal = len > 0.0001 ? normal / len : vec2(0.0);
  vec2 bend = -normal * uBend * edge;
  vec2 split = normal * uDispersion * edge;
  vec4 centre = ground(local + bend);
  float red = ground(local + bend + split).r;
  float blue = ground(local + bend - split).b;
  fragColor = vec4(red, centre.g, blue, centre.a);
}
