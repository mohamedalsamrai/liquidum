#version 460 core

// UIKit's glass (`UIGlassEffect`) for one shape: a box with rounded corners.
// The same material as the tab bar's platter (glass_material.glsl), with
// the inputs UIKit sets by the shape's size and style passed in.
//
// Two passes over the backdrop under the glass, as the bar's: the frost pass
// draws a light blur over a heavy one into the backdrop (where the glass will
// cover it), and the glass pass refracts that frost inward near the edge,
// colors it, lights its rim and shades what is around it.

#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;      // capture size in pixels (set by the engine)
uniform vec4 uShape;     // center.xy, half size.zw (capture pixels)
uniform vec4 uPass;      // pass (0 glass, 1 frost), pixels per point, corner radius (pixels), ovalization
uniform vec4 uOptics;    // inner refraction and its height (points), unused, refraction (0 to 1)
uniform vec4 uFace;      // face: luma black and white points, fill alpha, fill gray
uniform vec4 uRim;       // rim matrix: chroma gain, luma weight, lift; shadow strength
uniform vec4 uShadow;    // shadow: offset, sigma, center, reach (points)
uniform vec4 uMore;      // face chroma gain, unused, rim curvature, press wash
uniform vec4 uFrost;     // frost: full depth, light blur sigma (points), ramp power
uniform vec4 uGlow;      // fingertip glow: center.xy, 1 / (2 variance) (pixels), peak alpha
// The tint (UIGlassEffect.tintColor), as the bar's: at a gradient's start,
// over white glass (.rgb) with its alpha, and over black glass; the same at
// its end; the gradient's axis in capture pixels. [1].w: painted.
uniform vec4 uTints[5];
// Large glass's bleed (UIKit's glass filter blends a second rendering of the
// glass over it, more as the glass grows): [0..2] a color matrix taking the
// glass's color (and 1) to the bleed's red, green and blue; [3].x how much
// of it shows.
uniform vec4 uBleed[4];

uniform sampler2D uCapture;

out vec4 fragColor;

#include "glass_material.glsl"

// The frost lies within the glass by this many pixels (as the bar's).
const float kFrostInset = 2.0;

float glassDistance(vec2 p) {
  return continuousBox(p, uShape, uPass.z);
}

vec2 glassOutward(vec2 p, float oval) {
  return roundOutward(p, uShape, uPass.z, oval);
}

// p, moved into the glass's frost if it lies past it.
vec2 inFrost(vec2 p) {
  float over = glassDistance(p) + kFrostInset + 0.5;
  return over > 0.0 ? p - glassOutward(p, 0.0) * over : p;
}

void main() {
  vec2 p = FlutterFragCoord().xy;
  float k = uPass.y;
  float d = glassDistance(p);

  if (uPass.x > 0.5) {
    // ---- Frost pass: the light blur, over the heavy one.
    float depth = max(-d, 0.0) / k;
    // The light blur fades from half at the edge to none at the frost's
    // full depth, along a power of the depth.
    float light = 0.5 - 0.5 * pow(clamp((depth - 1.0) / (uFrost.x - 1.0), 0.0, 1.0), uFrost.z);
    fragColor = light > 0.0 ? vec4(lightFrost(p, uFrost.y * k) * light, light) : vec4(0.0);
    return;
  }

  // ---- Glass pass.
  float a = clamp(0.5 - d, 0.0, 1.0);
  vec3 c = vec3(0.0);
  if (a > 0.0) {
    float depth = max(-d, 0.0);
    vec2 n = glassOutward(p, uPass.w);
    vec2 q = p - n * uOptics.x * k * uOptics.w * sag(depth, uOptics.y * k);
    vec3 frosted = filtered(inFrost(q));
    // A painted color goes over the frosted backdrop in place of the face.
    c = tint(uTints[1].w > 0.5 ? frosted : glassFace(frosted, uFace, uMore.x), p,
             uTints[0], uTints[1], uTints[2], uTints[3], uTints[4]);
    if (uBleed[3].x > 0.0) {
      vec4 g = vec4(c, 1.0);
      vec3 bleed = clamp(vec3(dot(uBleed[0], g), dot(uBleed[1], g), dot(uBleed[2], g)), 0.0, 1.0);
      c = mix(c, bleed, uBleed[3].x);
    }
    float dp = depth / k;
    if (dp < kRimHeight + 0.5 / k) {
      c = rimLight(c, dp, glassOutward(p, 0.0), k, uMore.z, uRim.xyz, 1.0);
    }
    if (uMore.w > 0.0) {
      c = wash(c, uMore.w);
    }
    if (uGlow.w > 0.0) {
      vec2 g = p - uGlow.xy;
      c += uGlow.w * exp(-dot(g, g) * uGlow.z) * (1.0 - c);
    }
  }
  float shaded = 0.0;
  if (a < 1.0 && uRim.w > 0.0) {
    float ds = continuousBox(p - vec2(0.0, uShadow.x * k), uShape, uPass.z) / k;
    shaded = uRim.w * shadeAt(ds, uShadow.xyz, uShadow.w);
  }
  // The shadow darkens what is below, as black over it.
  fragColor = vec4(c * a, a + (1.0 - a) * shaded);
}
