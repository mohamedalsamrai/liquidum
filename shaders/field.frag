#version 460 core

// Draws the glass field flat, for checking geometry and motion against
// iOS: the platter, and the pill that clears into a lens.
//
// Coordinates are the canvas's local ones, in logical pixels.

#include <flutter/runtime_effect.glsl>

uniform vec4 uPlatter;   // center.xy, half size.xy
uniform vec4 uLens;      // center.xy, half size.xy
uniform vec4 uState;     // clear (0 pill .. 1 lens), ovalization, pixel size, mode

out vec4 fragColor;

// Signed distance to a capsule-cornered box (radius = half the short side).
float capsule(vec2 p, vec4 shape) {
  vec2 h = shape.zw;
  float r = min(h.x, h.y);
  vec2 q = abs(p - shape.xy) - h + r;
  return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

// Direction in which the distance grows, blended toward the inscribed
// ellipse's normal by `oval`.
vec2 normalOf(vec2 p, vec4 shape, float oval) {
  vec2 e = vec2(0.25, 0.0);
  vec2 g = vec2(capsule(p + e.xy, shape) - capsule(p - e.xy, shape),
                capsule(p + e.yx, shape) - capsule(p - e.yx, shape));
  g = length(g) > 0.0 ? normalize(g) : vec2(0.0);
  vec2 d = p - shape.xy;
  vec2 o = d / (shape.zw * shape.zw);
  o = length(o) > 0.0 ? normalize(o) : vec2(0.0);
  vec2 n = mix(g, o, oval);
  return length(n) > 0.0 ? normalize(n) : vec2(0.0);
}

vec4 over(vec4 top, vec4 under) {
  return top + under * (1.0 - top.a);
}

// Premultiplied color with coverage from a signed distance.
vec4 fill(float d, vec3 rgb, float px) {
  float a = clamp(0.5 - d / px, 0.0, 1.0);
  return vec4(rgb * a, a);
}

vec4 stroke(float d, float width, vec3 rgb, float px) {
  float a = clamp(0.5 - (abs(d + width * 0.5) - width * 0.5) / px, 0.0, 1.0);
  return vec4(rgb * a, a);
}

void main() {
  vec2 p = FlutterFragCoord().xy;
  float clear = uState.x;
  float oval = uState.y;
  float px = uState.z;
  float mode = uState.w;

  float dp = capsule(p, uPlatter);
  float dl = capsule(p, uLens);

  if (mode > 0.5) {
    // Normals of the lens, as colors, inside the lens only.
    vec2 n = normalOf(p, uLens, oval);
    vec4 platter = fill(dp, vec3(0.84), px);
    vec4 lens = fill(dl, vec3(0.5 + 0.5 * n.x, 0.5 + 0.5 * n.y, 0.5), px);
    fragColor = over(lens, platter);
    return;
  }

  // Platter: the light bar surface of the iOS tab bar over mid gray.
  vec4 color = fill(dp, vec3(0.84), px);
  color = over(stroke(dp, 1.0, vec3(0.93), px), color);

  // Pill: frosted and darker at rest, clear with a rim as a lens.
  vec3 pill = mix(vec3(0.74), vec3(0.90), clear);
  vec4 lens = fill(dl, pill, px);
  color = over(lens, color);
  // Lens rim, drawn only as it clears, in a saturated color so it can be
  // measured the same way as the native lens's chromatic rim.
  color = over(stroke(dl, 1.5, vec3(1.0, 0.0, 1.0), px) * clear, color);

  fragColor = color;
}
