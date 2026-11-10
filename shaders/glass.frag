#version 460 core

// UIKit's glass (`UIGlassEffect`) for up to eight shapes, boxes with rounded
// corners, as one glass group (`UIGlassContainerEffect`): the shapes melt
// together within the group's spacing. The same material as the tab bar's
// platter (glass_material.glsl), with the inputs UIKit sets by the shapes'
// sizes and style passed in. A lone glass is a group of one.
//
// Two passes over the backdrop under the glass, as the bar's: the frost pass
// draws a light blur over a heavy one into the backdrop where the glass will
// cover it (and puts the backdrop back elsewhere), and the glass pass
// refracts that frost inward near the edge, colors it, lights its rim and
// shades what is around it.

#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;      // capture size in pixels (set by the engine)
uniform vec4 uPass;      // pass (0 glass, 1 frost), pixels per point, shape count, ovalization
uniform vec4 uOptics;    // inner refraction and its height (points), spacing (pixels), refraction (0 to 1)
uniform vec4 uFace;      // face: luma black and white points, fill alpha, fill gray
uniform vec4 uRim;       // rim matrix: chroma gain, luma weight, lift; shadow strength
uniform vec4 uShadow;    // shadow: offset, sigma, center, reach (points)
uniform vec4 uMore;      // face chroma gain, pressed shape + 1 (0: none), rim curvature, press wash
uniform vec4 uFrost;     // frost: full depth, light blur sigma (points), ramp power
uniform vec4 uGlow;      // fingertip glow: center.xy, 1 / (2 variance) (pixels), peak alpha
// Each shape: center.xy and half size.zw (capture pixels); and its corner
// radius (pixels), how materialized it is (0 to 1), whether it melts with
// the others (1) or stands apart (0, while it dematerializes), whether it
// is tinted.
uniform vec4 uShapes[8];
uniform vec4 uShapeInfo[8];
// Each shape's tint (UIGlassEffect.tintColor), as the bar's: over white
// glass (.rgb) with its alpha, and over black glass (.rgb; .w: painted).
uniform vec4 uShapeTints[16];
// Large glass's bleed (UIKit's glass filter blends a second rendering of the
// glass over it, more as the glass grows): [0..2] a color matrix taking the
// glass's color (and 1) to the bleed's red, green and blue; [3].x how much
// of it shows.
uniform vec4 uBleed[4];
// A gray material over each shape (UIKit's prominent clear and disabled
// prominent glass buttons): the color times .x plus its luma times .y plus
// .z, at opacity .w (none at 0).
uniform vec4 uShapeMaterials[8];

uniform sampler2D uCapture;

out vec4 fragColor;

#include "glass_material.glsl"

const int kMaxShapes = 8;

// The frost lies within the glass by this many pixels (as the bar's).
const float kFrostInset = 2.0;

// A tint reaches past its shape's outline into the glass around it (a neck
// to a plain shape): fully up to 1.1pt out, none past 9pt (UIKit's, iOS
// 26.5, whatever the spacing).
const vec2 kTintReach = vec2(1.1, 9.0);

// UIKit's glass takes its shapes' outward direction (for refraction, the
// rim's light and how much two shapes face each other in a group) from a
// rounder box than the shape: corners 5/3 as large, up to half the short
// side, so near a corner it turns away well before the side meets the arc;
// the distances are the shapes' own. And, with uPass.w, UIKit's gradient
// ovalization (its SDF elements' 0.5 for regular glass over 64pt, or in a
// group whose largest glass is; none for clear glass): the direction leans
// halfway toward the point's in the box's normalized coordinates. Fitted to
// UIKit's silhouettes of squares and rectangles of 40 to 114pt, corners 4
// to 30 (unions), and to its glass over color (refraction) (iOS 26.5).
const float kGradientRound = 5.0 / 3.0;

// UIKit's fingertip glow (_UIFlexInteraction's little glow: a white disk's
// shadow drawn through a vibrant color matrix): what is under it, 2.727
// times itself less 0.909 times its luma (grays x1.82, colors deeper), by
// the glow's alpha (iOS 26.5).
vec3 glowLight(vec3 c, float alpha) {
  vec3 lit = clamp(2.7273 * c - 0.9091 * dot(c, kLuma), 0.0, 1.0);
  return mix(c, lit, alpha);
}

int shapeCount() {
  return int(uPass.z + 0.5);
}

// The group at p: its distance (returned) and outward direction n, from its
// shapes' own distances. UIKit's union (its SDF layer's smoothness is the
// container's spacing): every pair of melting shapes is blended by a
// quadratic smooth minimum as wide as the spacing times how much the two
// surfaces face each other (fully when they face, half when perpendicular,
// not at all side by side; directions as kGradientRound), and the group is
// the nearest of those blends and of the shapes alone. Fitted to UIKit's
// silhouettes within 0.1pt (iOS 26.5).
//
// slope: the group's gradient, which in a blend is shorter than 1 and
// vanishes at a neck's saddle (the refraction follows it there, so it fades
// through the middle of a neck rather than flipping across it, as UIKit's).
//
// Also, from the same distances: how materialized the glass is at p (each
// shape's own amount over its own outline, full elsewhere: a neck to a
// shape that is appearing is the group's from the start, as UIKit's), the
// amount of the shape nearest p, and the tint reaching p (its shape's
// index, or -1, and how much of it).
float groupAt(vec2 p, out vec2 n, out vec2 slope, out float amount,
              out float nearest, out int tinted, out float tintWeight) {
  int count = shapeCount();
  float d[kMaxShapes];
  vec2 g[kMaxShapes];
  float best = 1e9;
  n = vec2(0.0, -1.0);
  slope = n;
  amount = 1.0;
  nearest = 1.0;
  tinted = -1;
  tintWeight = 0.0;
  for (int i = 0; i < kMaxShapes; i++) {
    if (i >= count) {
      break;
    }
    d[i] = continuousBox(p, uShapes[i], uShapeInfo[i].x);
    g[i] = roundOutward(
        p, uShapes[i],
        min(uShapeInfo[i].x * kGradientRound, min(uShapes[i].z, uShapes[i].w)),
        uPass.w);
    if (d[i] < best) {
      best = d[i];
      n = g[i];
      slope = g[i];
      nearest = uShapeInfo[i].y;
    }
    if (uShapeInfo[i].y < 1.0) {
      amount = mix(amount, uShapeInfo[i].y, clamp(0.5 - d[i], 0.0, 1.0));
    }
    if (uShapeInfo[i].w > 0.5) {
      float w = 1.0 - smoothstep(kTintReach.x, kTintReach.y, d[i] / uPass.y);
      if (w > tintWeight) {
        tintWeight = w;
        tinted = i;
      }
    }
  }
  float spacing = uOptics.z;
  if (spacing <= 0.0 || count < 2) {
    return best;
  }
  for (int i = 0; i < kMaxShapes; i++) {
    if (i >= count) {
      break;
    }
    if (uShapeInfo[i].z < 0.5) {
      continue;
    }
    for (int j = 0; j < kMaxShapes; j++) {
      if (j >= count) {
        break;
      }
      if (j <= i || uShapeInfo[j].z < 0.5) {
        continue;
      }
      float k = spacing * 0.5 * (1.0 - dot(g[i], g[j]));
      float apart = abs(d[i] - d[j]);
      if (apart >= k) {
        continue;
      }
      float h = (k - apart) / k;
      float f = min(d[i], d[j]) - h * h * k * 0.25;
      if (f < best) {
        best = f;
        // The blend's gradient: the nearer shape's, leaning toward the
        // other's by half of h.
        float m = 0.5 * h;
        vec2 v = d[i] < d[j] ? mix(g[i], g[j], m) : mix(g[j], g[i], m);
        slope = v;
        n = length(v) > 1e-4 ? normalize(v) : g[i];
      }
    }
  }
  return best;
}

float groupDistance(vec2 p, out vec2 n) {
  vec2 slope;
  float amount;
  float nearest;
  int tinted;
  float tintWeight;
  return groupAt(p, n, slope, amount, nearest, tinted, tintWeight);
}

// p, moved into the glass's frost if it lies past it.
vec2 inFrost(vec2 p) {
  vec2 n;
  float over = groupDistance(p, n) + kFrostInset + 0.5;
  return over > 0.0 ? p - n * over : p;
}

void main() {
  vec2 p = FlutterFragCoord().xy;
  float k = uPass.y;
  vec2 n;
  vec2 slope;
  float amount;
  float nearest;
  int tinted;
  float tintWeight;
  float dist = groupAt(p, n, slope, amount, nearest, tinted, tintWeight);

  if (uPass.x > 0.5) {
    // ---- Frost pass: the light blur over the heavy one within the frost,
    // and the backdrop as it was outside it (the heavy blur covers the
    // group's bounds). Partly materialized glass has as much frost, as
    // UIKit's (its frost's opacities follow the amount, and its blur
    // radius: here the heavy blur's sigma follows the group's amount).
    float frost = clamp(-(dist + kFrostInset) + 0.5, 0.0, 1.0) * amount;
    vec3 sharp = capture(p);
    float alpha = 0.0;
    vec3 light = vec3(0.0);
    if (frost > 0.0) {
      float depth = max(-dist, 0.0) / k;
      float full = max(uFrost.x * amount, 1.5);
      // The light blur fades from half at the edge to none at the frost's
      // full depth, along a power of the depth.
      float l = 0.5 - 0.5 * pow(clamp((depth - 1.0) / (full - 1.0), 0.0, 1.0), uFrost.z);
      alpha = l * frost;
      if (alpha > 0.0) {
        light = lightFrost(p, max(uFrost.y * amount, 0.05) * k);
      }
    }
    fragColor = vec4(light * alpha + (1.0 - alpha) * (1.0 - frost) * sharp,
                     1.0 - (1.0 - alpha) * frost);
    return;
  }

  // ---- Glass pass.
  float a = clamp(0.5 - dist, 0.0, 1.0);
  vec3 c = vec3(0.0);
  if (a > 0.0) {
    float depth = max(-dist, 0.0);
    vec2 q = p - slope * uOptics.x * amount * k * uOptics.w *
                 sag(depth, max(uOptics.y * amount * k, 1e-3));
    vec3 frosted = filtered(inFrost(q));
    // The face, from none to UIKit's as the glass materializes: its inputs
    // and its opacity both follow the amount.
    vec4 face = vec4(uFace.x * amount, 1.0 + (uFace.y - 1.0) * amount,
                     uFace.z * amount, uFace.w);
    c = mix(frosted, glassFace(frosted, face, mix(1.0, uMore.x, amount)), amount);
    // The tint of the shape whose tint reaches here.
    for (int i = 0; i < kMaxShapes; i++) {
      if (i == tinted) {
        vec4 bright = uShapeTints[2 * i];
        vec4 dark = uShapeTints[2 * i + 1];
        c = mix(c, tint(c, p, bright, dark, bright, dark, vec4(0.0)), tintWeight);
      }
    }
    // The material over the shape at p (within its own outline).
    for (int i = 0; i < kMaxShapes; i++) {
      if (i >= shapeCount()) {
        break;
      }
      vec4 m = uShapeMaterials[i];
      if (m.w > 0.0) {
        float inside = clamp(0.5 - continuousBox(p, uShapes[i], uShapeInfo[i].x), 0.0, 1.0);
        vec3 gray = clamp(m.x * c + m.y * dot(c, kLuma) + m.z, 0.0, 1.0);
        c = mix(c, gray, m.w * inside * amount);
      }
    }
    if (uBleed[3].x > 0.0) {
      vec4 b = vec4(c, 1.0);
      vec3 bleed = clamp(vec3(dot(uBleed[0], b), dot(uBleed[1], b), dot(uBleed[2], b)), 0.0, 1.0);
      c = mix(c, bleed, uBleed[3].x * amount);
    }
    // The rim, by true distance: where shapes blend the field grows slower
    // than distance (its gradient is shorter than 1), and UIKit's rim keeps
    // its width there.
    float dp = depth / k / max(length(slope), 0.25);
    if (dp < kRimHeight + 0.5 / k) {
      c = rimLight(c, dp, n, k, uMore.z, uRim.xyz, amount);
    }
    // The press, over the pressed shape (and a little into a neck from it,
    // as a tint): its wash, and the glow under the finger.
    int pressed = int(uMore.y + 0.5) - 1;
    if (pressed >= 0 && (uMore.w > 0.0 || uGlow.w > 0.0)) {
      float reach = 1.0;
      for (int i = 0; i < kMaxShapes; i++) {
        if (i == pressed && shapeCount() > 1) {
          float di = continuousBox(p, uShapes[i], uShapeInfo[i].x) / k;
          reach = 1.0 - smoothstep(kTintReach.x, kTintReach.y, di);
        }
      }
      if (uMore.w > 0.0) {
        c = mix(c, wash(c, uMore.w), reach);
      }
      if (uGlow.w > 0.0) {
        vec2 o = p - uGlow.xy;
        c = glowLight(c, reach * uGlow.w * exp(-dot(o, o) * uGlow.z));
      }
    }
  }
  float shaded = 0.0;
  if (a < 1.0 && uRim.w > 0.0) {
    vec2 ns;
    vec2 slopeS;
    float amountS;
    float nearestS;
    int tintedS;
    float tintS;
    float far = groupAt(p - vec2(0.0, uShadow.x * k), ns, slopeS, amountS, nearestS, tintedS, tintS) / k;
    shaded = uRim.w * nearestS * shadeAt(far, uShadow.xyz, uShadow.w);
  }
  // The shadow darkens what is below, as black over it.
  fragColor = vec4(c * a, a + (1.0 - a) * shaded);
}
