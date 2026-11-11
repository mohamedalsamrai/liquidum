#version 460 core

// UIKit's liquid lens (`_UILiquidLensView`) on its own, over whatever is
// painted behind it: the thumb of a switch or a slider, the selection of a
// segmented control. The tab bar's lens (backdrop.frag's lens pass) with
// the same optics (lens_material.glsl), over a plain backdrop instead of
// the bar's platter and its tabs:
//
// - At rest, the resting pill: what is behind the lens, blurred, under a
//   color matrix (uPill), fading out as the lens lifts.
// - Lifted, the lens's material fades in at four times the lift progress
//   over the warped backdrop (pushed outward by up to 9pt at full lift,
//   never read from outside the lens's bounds), seen through an inner
//   refraction a few points deep, dispersed near the edge, under the lens's
//   tone and top shade and its tint; its rim over it and its shadow around
//   it.
// - What differs from the bar's: there is no platter below the lens (the
//   bare backdrop lies under it everywhere, with no platter shadow), and no
//   lifted content: the bar renders its selected tabs into an atlas and
//   lenses them into the lens by UIKit's content displacement (17.5pt, grown
//   16%); here, anything under the lens (a track, a label) is backdrop, and
//   is warped and refracted as a backdrop is. The resting pill's blur is in
//   the lens's own points (the bar's is in its platter's, which rest at the
//   same scale).

#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;      // capture size in pixels (set by the engine)
uniform vec4 uPass;      // unused, unused, pixels per point, ovalization
uniform vec4 uLens;      // lens as drawn: center.xy, half size.xy (capture pixels)
uniform vec4 uOptics;    // lift progress, lens scale, unused, stages (bit mask)
uniform vec4 uLensRim;   // lens rim matrix: chroma gain, luma weight, lift; unused
uniform vec4 uPill;      // resting pill matrix: chroma gain, luma weight, lift; unused
uniform vec4 uShow;      // how much the lens shows (its opacity); unused x3
// The lens's own inputs (LensOptics): UIKit scales its liquid lens's by its
// lifted height, and its small lens (the switch's and slider's thumbs) has
// inputs of its own.
uniform vec4 uInner;     // inner refraction amount and height (points), lifted blur sigma (points), shadow strength
uniform vec4 uFace;      // face black point, rim strength, unused x2
// Tints (GlassDecoration) of the resting pill (0-4) and the lifted lens
// (5-9), each as backdrop.frag's: at a gradient's start, over white glass
// (.rgb) with its alpha, and over black glass ([1].w: painted as it is);
// the same at its end; the gradient's axis in capture pixels.
uniform vec4 uTints[10];
#define REST_TINT uTints[0], uTints[1], uTints[2], uTints[3], uTints[4]
#define LENS_TINT uTints[5], uTints[6], uTints[7], uTints[8], uTints[9]

uniform sampler2D uCapture;

out vec4 fragColor;

#include "glass_material.glsl"
#include "lens_material.glsl"

// What the lens sees below it, over a pixel's footprint there (the
// mapping's columns j1, j2 for one pixel across and down): the backdrop
// averaged over the footprint, which the lens compresses many times near
// its rim (backdrop.frag's `below`, without the platter).
vec3 below(vec2 p, vec2 j1, vec2 j2) {
  vec2 a = 0.5 * j1, b = 0.5 * j2;
  return 0.25 * (filtered(p - a - b) + filtered(p + a - b) + filtered(p - a + b) +
                 filtered(p + a + b));
}

// Gaussian blur around p: a Vogel spiral out to 2.5 sigma, each tap
// filtered (backdrop.frag's `frost` of the bare backdrop).
vec3 blur(vec2 p, float sigma, int taps) {
  vec3 sum = vec3(0.0);
  float total = 0.0;
  for (int i = 0; i < 32; i++) {
    if (i >= taps) {
      break;
    }
    float t = (float(i) + 0.5) / float(taps);
    float r = sqrt(t) * 2.5;
    float a = float(i) * 2.39996323;
    float w = exp(-0.5 * r * r);
    vec2 at = p + vec2(cos(a), sin(a)) * r * sigma;
    sum += filtered(at) * w;
    total += w;
  }
  return sum / total;
}

// What the lens material has behind it at q: the warped backdrop, with the
// resting pill over it until the lens lifts (backdrop.frag's `base`). UIKit
// renders the warped backdrop as an image that the material then resamples
// and magnifies, so it is averaged here over one pixel of that image. A
// small lens blurs it (its glass filter's blur radius 2), as its material
// fades in.
vec3 base(vec2 q, float lift) {
  vec2 s = warpSource(q, lift);
  vec2 j1 = warpSource(q + vec2(1.0, 0.0), lift) - s;
  vec2 j2 = warpSource(q + vec2(0.0, 1.0), lift) - s;
  vec3 w = below(s, j1, j2);
  float k = uPass.z * uOptics.y;
  if (uInner.z > 0.0 && lift > 0.0) {
    w = mix(w, blur(s, uInner.z * k, 16), clamp(kMaterialFade * lift, 0.0, 1.0));
  }
  if (lift < 1.0 && stage(kRestStage)) {
    vec3 behind = blur(s, kRestBlur * k, 16);
    // A painted color goes over the glass behind, in place of the pill's
    // own matrix.
    vec3 rest = tint(uTints[1].w > 0.5 ? behind : vibrant(behind, uPill.xyz), q, REST_TINT);
    w = mix(rest, w, lift);
  }
  return w;
}

// The lens's material at p: the base seen through the inner refraction
// (by the lens's own amount and height), lifted by the face's black point,
// under the tone, the top shade and the tint.
vec3 material(vec2 p, float lift, float tone) {
  vec2 inner = innerSourceWith(p, uInner.x, uInner.y);
  vec3 b = base(inner, lift);
  b += uFace.x * (1.0 - b);
  return tint(b * tone * topShade(inner), p, LENS_TINT);
}

void main() {
  vec2 p = FlutterFragCoord().xy;
  float px = uPass.z;          // one point, in pixels
  float lift = uOptics.x;
  float show = uShow.x;

  // The resting pill fading into the clear lens, and around it the lens's
  // shadow, over all that is below it.
  float d = capsule(p, uLens);
  float a = coverage(d, 1.0);
  float k = px * uOptics.y;
  float fade = clamp(kMaterialFade * lift, 0.0, 1.0);
  float shadow = 0.0;
  if (a < 1.0 && fade > 0.0 && stage(kShadowStage)) {
    shadow = uInner.w * fade * shade(p, uLens, k, kLensShadow, kLensShadowReach);
  }
  if (a <= 0.0) {
    fragColor = vec4(0.0, 0.0, 0.0, shadow) * show;
    return;
  }
  float depth = max(-d, 0.0);
  float tone = stage(kInnerStage) ? kLensTone : 1.0;
  // The material fades in quickly as the lens lifts (as UIKit's does),
  // over the base: the resting pill over the warped backdrop.
  vec3 c = fade < 1.0 ? base(p, lift) : vec3(0.0);
  if (fade > 0.0) {
    // The material, dispersed near the edge. A tap past the lens's outline
    // reads the unwarped backdrop, as UIKit's warp is clipped to the
    // outline.
    vec3 glass = material(p, lift, tone);
    float spread = clamp(1.0 - depth / (kAberrationDepth * k), 0.0, 1.0);
    if (spread > 0.0 && stage(kDispersionStage)) {
      vec2 v = kAberration * ((p - uLens.xy) / uLens.zw) * k;
      vec4 texels = lensTexels();
      vec3 dispersed = vec3(0.0);
      for (int i = 0; i < 7; i++) {
        float t = float(i - 3) / 3.0;
        vec3 w = vec3(max(t, 0.0) * 0.5, (1.0 - abs(t)) / 3.0, max(-t, 0.0) * 0.5);
        vec2 at = clamp(p + v * t, texels.xy, texels.zw);
        vec3 s = i == 3 ? glass
                        : capsule(at, uLens) < 0.0
                              ? material(at, lift, tone)
                              : below(at, vec2(1.0, 0.0), vec2(0.0, 1.0));
        dispersed += w * s;
      }
      glass = mix(glass, dispersed, spread);
    }
    c = mix(c, glass, fade);
  }
  if (stage(kRimStage)) {
    c = rim(c, p, uLens, k, kLensRimCurvature, uLensRim.xyz, fade * uFace.y);
  }
  fragColor = vec4(c * a, a + (1.0 - a) * shadow) * show;
}
