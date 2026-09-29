// Liquid glass: a single backdrop pass.
//
// The engine binds the (optionally pre-blurred) backdrop to `uBackdrop` and
// its pixel size to `uSize`. `FlutterFragCoord()` is in the same pixel space,
// so every geometric uniform below is in physical pixels of that space.
//
// The optics follow measurements of iOS 26 glass rather than a textbook lens:
// every pixel looks inward, towards the middle of the shape, by a distance
// that is largest at the edge and decays exponentially. Near the edge the
// distance exceeds the pixel's own depth, so the rim shows a mirrored,
// magnified image of the interior. Outside the shape the pass only writes the
// soft shadow and is transparent otherwise, leaving the backdrop untouched.

#version 460 core

#include <flutter/runtime_effect.glsl>

precision highp float;

uniform vec2 uSize;

// Shape: center.xy, halfSize.zw; corner radius.
uniform vec4 uRect;
uniform float uRadius;

// Refraction: inward reach at the edge, its decay length, channel spread.
uniform float uRefraction;
uniform float uFalloff;
uniform float uDispersion;

// Lengthwise lens of elongated shapes: reach at the ends, decay length.
uniform vec2 uEnds;

// Scale of what the glass shows, about its center (below 1 shows more).
uniform float uZoom;

// Appearance.
uniform float uSaturation;
uniform float uResponse;
uniform float uLift;
uniform vec4 uTint;

// Rim light: unit axis towards the light in screen space, strength, width,
// and how much it gathers along that axis (0 lights the rim evenly).
uniform vec2 uLight;
uniform float uSpecular;
uniform float uRim;
uniform float uLightFocus;

// Shadow: offset.xy, softness (sigma), opacity.
uniform vec4 uShadow;

uniform sampler2D uBackdrop;

out vec4 fragColor;

float sdRoundRect(vec2 p, vec2 b, float r) {
  vec2 q = abs(p) - b + r;
  return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

// Outward unit normal of the rounded rect's edge nearest to `p`.
vec2 edgeNormal(vec2 p, vec2 b, float r) {
  vec2 q = abs(p) - b + r;
  vec2 g = max(q.x, q.y) > 0.0 ? max(q, 0.0)
                               : (q.x > q.y ? vec2(1.0, 0.0) : vec2(0.0, 1.0));
  g /= max(length(g), 1e-4);
  return vec2(p.x < 0.0 ? -g.x : g.x, p.y < 0.0 ? -g.y : g.y);
}

vec4 backdrop(vec2 px) {
  vec2 uv = px / uSize;
#ifdef IMPELLER_TARGET_OPENGLES
  uv.y = 1.0 - uv.y;
#endif
  return texture(uBackdrop, uv);
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  vec2 p = frag - uRect.xy;
  vec2 halfSize = uRect.zw;

  float sd = sdRoundRect(p, halfSize, uRadius);
  float coverage = clamp(0.5 - sd, 0.0, 1.0);

  // Soft shadow of the slab, only visible outside of it.
  float shadowSd = sdRoundRect(p - uShadow.xy, halfSize, uRadius);
  float shadow = uShadow.w / (1.0 + exp(1.702 * shadowSd / max(uShadow.z, 1e-3)));
  vec4 outside = vec4(0.0, 0.0, 0.0, shadow);

  if (coverage <= 0.0) {
    fragColor = outside;
    return;
  }

  float depth = max(-sd, 0.0);
  vec2 edge = edgeNormal(p, halfSize, uRadius);

  // Inward reach, faded out towards the middle line.
  float middle = min(halfSize.x, halfSize.y);
  float reach = uRefraction * exp(-depth / max(uFalloff, 1e-3));
  reach *= 1.0 - smoothstep(0.7, 1.0, depth / middle);

  // Bend along a superellipse fitted to the shape rather than along `edge`:
  // `edge` stays fixed along straight sides and turns only at the corners,
  // which leaves flat, creased bands; this turns smoothly all the way round.
  float n = mix(8.0, 2.5, clamp(uRadius / middle, 0.0, 1.0));
  vec2 q = max(abs(p) / halfSize, vec2(1e-4));
  vec2 bend = pow(q, vec2(n - 1.0)) / halfSize;
  bend = normalize(bend) * vec2(p.x < 0.0 ? -1.0 : 1.0, p.y < 0.0 ? -1.0 : 1.0);
  vec2 look = -bend * reach;

  // Elongated shapes also look inward along their length, increasingly
  // towards the ends, which magnifies what is under them there.
  bool wide = halfSize.x >= halfSize.y;
  vec2 axis = wide ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
  float major = max(halfSize.x, halfSize.y);
  float along = dot(p, axis);
  float elongation = clamp((major - middle) / middle, 0.0, 1.0);
  float ends = uEnds.x * elongation *
               exp(-(major - abs(along)) / max(uEnds.y, 1e-3)) *
               smoothstep(0.0, 0.3 * major, abs(along));
  look -= axis * sign(along) * ends;

  look += p * (1.0 / max(uZoom, 1e-3) - 1.0);

  vec3 color;
  if (uDispersion > 0.0) {
    color.r = backdrop(frag + look * (1.0 + uDispersion)).r;
    color.g = backdrop(frag + look).g;
    color.b = backdrop(frag + look * (1.0 - uDispersion)).b;
  } else {
    color = backdrop(frag + look).rgb;
  }

  // Material response: a veil that compresses and lifts the backdrop, then
  // saturation around the new luminance, then tint.
  color = color * uResponse + uLift;
  float luma = dot(color, vec3(0.2126, 0.7152, 0.0722));
  color = luma + (color - luma) * uSaturation;
  color = mix(color, uTint.rgb, uTint.a);

  // Rim light: a thin band that fades linearly inward. Focused, it is lit
  // along the light axis in both directions and absent on the diagonals
  // across it; unfocused, it is even all the way round.
  float rim = clamp(1.0 - depth / max(uRim, 1e-3), 0.0, 1.0);
  float lobe = mix(
      1.0, max(abs(dot(edge, uLight)) - 0.25, 0.0) / 0.75, uLightFocus);
  color = mix(color, vec3(1.0), uSpecular * rim * lobe);

  vec4 glass = vec4(clamp(color, 0.0, 1.0), 1.0);
  fragColor = mix(outside, glass, coverage);
}
