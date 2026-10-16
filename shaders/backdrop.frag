#version 460 core

// One shader for every pass over a glass tab bar's shared backdrop: the
// bar's glass, the lens's glass, and a diagnostic inspector. All three read
// the same capture, taken before any of the bar's glass is drawn, and work
// in its coordinates: physical pixels of the pass it was captured from.
//
// The optics follow UIKit's own tab bar on iOS 26.5, each stage measured on
// its own in the simulator over position-coded backdrops.
//
// - The platter (regular glass) frosts what is below it (more toward its
//   middle line), refracts that inward near its edge, and lifts luma toward
//   white while keeping 73% of the chroma. The frost is a real blur, drawn
//   before these passes into the backdrop under the platter (the bar's
//   frost pass), so the capture holds it there: a pixel the platter covers
//   reads already frosted.
// - The lens looks at what is below it: the platter where it covers it, the
//   bare backdrop past its edge. Below the lens's material lie the warp,
//   which pushes samples outward by up to 9pt at full lift (the one optical
//   parameter the lift drives) and never reads outside the lens's bounds,
//   so the backdrop at the bounds is stretched across the rim, and over it
//   the resting selection (the glass behind, blurred, under a color matrix)
//   fading out as the lens lifts. The material sees that through an inner
//   refraction a few points deep, disperses it near the edge (red and blue
//   pulled apart), and fades in over it at four times the lift progress.
// - The tabs are lifted into the lens: the selected-style tabs (an atlas the
//   bar renders), each grown 16% about its center at full lift, clipped to
//   the lens, pulled inward near its edge by two displacement maps (17.5pt
//   at full lift, 11.2pt and 14pt high), and dispersed with the material.
// - The lighting belongs to the glass too: a rim lit from up-left and
//   down-right on the platter and on the lens, a shadow under each (the
//   platter's lighter over brighter backdrops), and, while pressed, a wash
//   and a fingertip glow over the platter and its tabs (the bar draws the
//   glow). The lens sees all of the platter's lighting below it, through
//   its optics and under its tone; only its own rim lies over it.

#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;        // capture size in pixels (set by the engine)
uniform vec4 uPass;        // pass (0 bar, 1 lens, 2 inspector, 3 frost), diagnostic, pixels per point, ovalization
uniform vec4 uPlatter;     // platter: center.xy, half size.xy
uniform vec4 uLens;        // lens as drawn: center.xy, half size.xy
uniform vec4 uOptics;      // lift progress, lens scale, platter scale, stages (debug: bit mask)
uniform vec4 uTouch;       // finger.xy, pressed, press amount (the wash)
uniform vec4 uInspector;   // inspector on screen: origin.xy, size.xy
uniform vec4 uWindow;      // capture window it shows: origin.xy, size.xy
uniform vec4 uContent;     // the bar's origin in capture pixels.xy, the content atlas's size as rendered in points.zw
uniform vec4 uTabs;        // first tab's center x, spacing, count, atlas slot pitch (points)
uniform vec4 uPlatterXf;   // platter transform: center.xy, drift.xy (points)
uniform vec4 uPlatterS;    // platter scale.xy, content row height, atlas slot width (points)
uniform vec4 uGlow;        // fingertip glow: center.xy, 1 / (2 variance) (pixels), peak alpha
// The adaptive appearance (GlassAppearance): the glass's color inputs as
// they follow the backdrop's luma and the light or dark appearance.
uniform vec4 uFace;        // platter face: luma black and white points, fill alpha, fill gray
uniform vec4 uRim;         // platter rim matrix: chroma gain, luma weight, lift; platter shadow strength
uniform vec4 uLensRim;     // lens rim matrix: chroma gain, luma weight, lift; symbols' lift
uniform vec4 uPill;        // resting selection matrix: chroma gain, luma weight, lift; symbols' luma weight
// Tints (UIGlassEffect.tintColor) of the platter (0-4), the resting
// selection (5-9) and the lifted lens (10-14), each: at a gradient's start,
// over white glass (.rgb) with its alpha, and over black glass; the same at
// its end; the gradient's axis in capture pixels, start.xy and end.xy (a
// single color: the same twice, no axis). [1].w: painted as it is rather
// than tinted (GlassFill.paint). One array: Metal gives each
// uniform a buffer, and has 31.
uniform vec4 uTints[15];
#define GLASS_TINT uTints[0], uTints[1], uTints[2], uTints[3], uTints[4]
#define REST_TINT uTints[5], uTints[6], uTints[7], uTints[8], uTints[9]
#define LENS_TINT uTints[10], uTints[11], uTints[12], uTints[13], uTints[14]
uniform vec4 uSelected;    // selected symbols: offset added to half of what is below them and the tint; content rows' top in the bar (points); selected symbols in their color as it is (Increase Contrast, flag); content drawn as it is (flag)
// Glass beside the platter, of the same glass (UIKit's search tab or its
// search field, the bottom accessory, and the search field's close
// button): each center.xy and half size.zw in capture pixels, none at zero
// size. [3]: how much the tabs' content and the selection show (both fade
// as the bar collapses), the face's chroma gain and how much the glass
// refracts (both less for Increase Contrast and Reduce Transparency).
// [4]: the tabs' content blur as it fades (a gaussian sigma in points).
uniform vec4 uExtra[5];
#define GLASS_SHAPES 3
#define CONTENT uExtra[3]

uniform sampler2D uCapture;
uniform sampler2D uContentAtlas;  // the tabs' content: a row per layer, a slot per tab

out vec4 fragColor;

// ---- UIKit's numbers, in the glass's own points.

// Lens: the warp's displacement at full lift and the height of the lens's
// glass displacement.
const float kWarp = 9.0;
const float kWarpHeight = 36.0;
// Lens glass filter: inner refraction amount and height, SDR holding tone.
const float kLensInner = 17.5;
const float kLensInnerHeight = 7.0;
const float kLensTone = 0.97;
// Lens dispersion (aberration amount 3.68, offset 38.9, angle -15
// degrees): the image is dispersed over seven taps along a vector that grows
// with the position (x / half width, y / half height); red takes the three
// taps toward one end (1:2:3), blue the mirror, green the middle five
// (1:2:3:2:1). Mixed in fully at the edge, not at all 14pt in.
const float kAberrationDepth = 14.0;
const mat2 kAberration = mat2(-1.499, 2.235, 5.925, 0.706);
// Platter glass filter: inner refraction. Its frost is in the capture
// already, within the platter less this many pixels: the bar draws it
// there before its other passes, a heavy blur (natively) and over it a
// light one (this shader's frost pass), at what the platter holds of the
// light one: half at its edge, none 31pt in (as UIKit's glass filter mixes
// its heavy blur into its quarter-scale capture, measured in the
// simulator), along a power of the depth. The light blur's sigma is in
// points; it and the power are fitted to UIKit's frost over stripes.
const float kPlatterInner = 49.6;
const float kPlatterInnerHeight = 15.5;
const float kFrostInset = 2.0;
const float kFrostLight = 0.46;
const float kFrostFullDepth = 31.0;
const float kFrostRamp = 0.72;
// Its face color matrix (the luma mapped from a black to a white point, the
// chroma kept, a fill mixed in; inputs in uFace) sits under the filter's
// 0.97 SDR holding tone.
const float kPlatterTone = 0.97;
// The resting selection blurs the glass behind it again (a gaussian blur,
// radius 2 at quarter scale), then applies a color matrix (uPill).
const float kRestBlur = 2.22;
// Lifted content (UIKit's displacement of the lens's content): the selected
// tabs, seen in the lens, are lensed by two displacement maps of this amount
// at full lift (one of height 11.2, then one of height 14 in the material),
// each pulling inward near the edge.
// UIKit also scales each selected tab by 1.16 about its center at full lift.
const float kContentLens = 17.5;
const float kContentLensHeight = 11.2;
const float kContentMaterialHeight = 14.0;
const float kContentGrowth = 0.16;
// UIKit fades the lens's material in at four times the lift progress.
const float kMaterialFade = 4.0;

// ---- Lighting.

// Rim (UIKit's rim highlight): a key light from up-left and a fill
// from down-right at equal amounts light a 1pt band inside the edge by
// |n.l|, fading toward its inner side by the effect's curvature (platter
// 0.7, lens 0.8); measured alpha = |n.l| (1 - curvature u), u the depth
// over the band, within 1-4% of UIKit's rim at every angle. Its vibrant
// color matrix (uRim, uLensRim) pushes what is below toward a gain of its
// chroma plus a weight of its luma and a lift.
const vec2 kLight = vec2(0.70710678, 0.70710678);
const float kRimHeight = 1.0;
const float kPlatterRimCurvature = 0.7;
const float kLensRimCurvature = 0.8;
// Shadows (from the glass filter): outside the glass, what is below is
// multiplied by 1 - strength * (a gaussian edge of the outline moved down);
// the edge's sigma is 0.685 of the filter's shadow radius. (offset, sigma,
// center) in points. The strength is opacity * (0.093 + 0.966 fill): the
// lens's fill is black; the platter's adapts to the backdrop (uRim.w). Both
// fit UIKit's within 0.3 levels; the platter's stops where its SDF does.
const vec3 kPlatterShadow = vec3(8.0, 16.4, 0.85);
const float kPlatterShadowReach = 39.06;
const vec3 kLensShadow = vec3(7.0, 5.49, 0.05);
const float kLensShadowStrength = 0.1086;
const float kLensShadowReach = 9.21;
// Inside, the lens's material darkens what it reads where its shadow's
// edge is not: most just inside its top edge, and none past 15pt in (by
// this much over what is below, wherever the shadow there would be none).
// Fitted to UIKit's lifted lens over white, gray and a position code; a
// shadow opacity of 0.111 in its glass filter is the likely source.
const float kLensTopShade = 0.06;
// The press wash (a white layer over the platter through a vibrant color
// matrix): chroma x1.2 and a 0.05 lift, at 0.8448 when fully pressed.
const float kWash = 0.8448;

const vec3 kLuma = vec3(0.2126, 0.7152, 0.0722);

// Stages, for comparing them one at a time (GlassTabBar's debugOptics).
const float kWarpStage = 1.0;
const float kInnerStage = 2.0;
const float kDispersionStage = 4.0;
const float kPlatterStage = 8.0;
const float kRestStage = 16.0;
const float kContentStage = 32.0;
const float kRimStage = 64.0;
const float kShadowStage = 128.0;
const float kPressStage = 256.0;

bool stage(float bit) {
  return mod(floor(uOptics.w / bit), 2.0) > 0.5;
}

// ---- Geometry, in capture pixels.

// Signed distance to a capsule-cornered box (radius = half the short side).
float capsule(vec2 p, vec4 s) {
  vec2 h = s.zw;
  float r = min(h.x, h.y);
  vec2 q = abs(p - s.xy) - h + r;
  return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

// Outward direction of the capsule's distance, blended by `oval` toward the
// direction of the point in the capsule's normalized coordinates (x / half
// width, y / half height): the ovalization of UIKit's glass shapes, which
// this matches to within 1.3 degrees (median) over its lens's displacement
// field.
vec2 outward(vec2 p, vec4 s, float oval) {
  vec2 d = p - s.xy;
  vec2 h = s.zw;
  float r = min(h.x, h.y);
  vec2 q = abs(d) - h + r;
  vec2 g;
  if (q.x > 0.0 && q.y > 0.0) {
    g = normalize(q);
  } else {
    g = q.x > q.y ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
  }
  g *= vec2(d.x < 0.0 ? -1.0 : 1.0, d.y < 0.0 ? -1.0 : 1.0);
  vec2 o = d / h;
  o = length(o) > 0.0 ? normalize(o) : g;
  vec2 n = mix(g, o, oval);
  return length(n) > 0.0 ? normalize(n) : g;
}

// The glass shape nearest p: the platter, or one beside it.
vec4 glassAt(vec2 p) {
  vec4 s = uPlatter;
  float d = capsule(p, uPlatter);
  for (int i = 0; i < GLASS_SHAPES; i++) {
    if (uExtra[i].z > 0.0) {
      float e = capsule(p, uExtra[i]);
      if (e < d) {
        d = e;
        s = uExtra[i];
      }
    }
  }
  return s;
}

float glassDistance(vec2 p) {
  return capsule(p, glassAt(p));
}

// UIKit's glass displacement profile: the sag of a circular arc, 1 at the
// edge, 0 at `height` in.
float sag(float depth, float height) {
  float u = clamp(1.0 - depth / height, 0.0, 1.0);
  return 1.0 - sqrt(1.0 - u * u);
}

// ---- Sampling.

// Texture coordinates for a point in an image that is `size` big, top-left
// origin. Impeller's GLES backend keeps the textures it renders to (the
// capture, and the content atlas) upside down.
vec2 texel(vec2 p, vec2 size) {
  vec2 uv = p / size;
#ifdef IMPELLER_TARGET_OPENGLES
  uv.y = 1.0 - uv.y;
#endif
  return uv;
}

vec3 capture(vec2 p) {
  return texture(uCapture, texel(p, uSize)).rgb;
}

// The capture at p, between its four nearest pixels: the engine samples it
// at the nearest one only.
vec3 filtered(vec2 p) {
  vec2 q = p - 0.5;
  vec2 i = floor(q);
  vec2 f = q - i;
  vec2 c = i + 0.5;
  return mix(mix(capture(c), capture(c + vec2(1.0, 0.0)), f.x),
             mix(capture(c + vec2(0.0, 1.0)), capture(c + vec2(1.0)), f.x), f.y);
}

// p, moved into the glass's frost if it lies past it.
vec2 inFrost(vec2 p) {
  vec4 g = glassAt(p);
  float over = capsule(p, g) + kFrostInset + 0.5;
  return over > 0.0 ? p - outward(p, g, 0.0) * over : p;
}

// A small gaussian blur around p (sigma up to about 2 pixels): the pixels
// within 2 of it, but the corners.
vec3 lightFrost(vec2 p, float sigma) {
  float e = -0.5 / (sigma * sigma);
  vec3 sum = vec3(0.0);
  float total = 0.0;
  for (int y = -2; y <= 2; y++) {
    for (int x = -2; x <= 2; x++) {
      if (abs(float(x)) + abs(float(y)) > 3.0) {
        continue;
      }
      float w = exp(float(x * x + y * y) * e);
      sum += capture(p + vec2(float(x), float(y))) * w;
      total += w;
    }
  }
  return sum / total;
}

// Gaussian blur around p: a Vogel spiral out to 2.5 sigma. `frosted`: of
// the platter's frost, kept within it, and smooth enough there to read each
// tap at its nearest pixel; elsewhere each tap is filtered.
vec3 frost(vec2 p, float sigma, int taps, bool frosted) {
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
    sum += (frosted ? capture(inFrost(at)) : filtered(at)) * w;
    total += w;
  }
  return sum / total;
}

// The platter's face over its frosted backdrop c.
vec3 face(vec3 c) {
  float l = dot(c, kLuma);
  vec3 f = uFace.x + (uFace.y - uFace.x) * l + (c - l) * CONTENT.z;
  return clamp(kPlatterTone * mix(f, vec3(uFace.w), uFace.z), 0.0, 1.0);
}

// UIKit's tinted glass at p: a color matrix over the glass c taking its
// luma to a color between the tint over black glass and over white glass,
// mixed in at the tint's alpha. A gradient's tint goes from its start's to
// its end's along its axis. A painted one is its color over c, at its alpha.
vec3 tint(vec3 c, vec2 p, vec4 bright1, vec4 dark1, vec4 bright2, vec4 dark2, vec4 axis) {
  if (bright1.a <= 0.0 && bright2.a <= 0.0) {
    return c;
  }
  vec2 v = axis.zw - axis.xy;
  float span = dot(v, v);
  float t = span > 0.0 ? clamp(dot(p - axis.xy, v) / span, 0.0, 1.0) : 0.0;
  vec4 bright = mix(bright1, bright2, t);
  if (dark1.w > 0.5) {
    return mix(c, bright.rgb, bright.a);
  }
  vec3 dark = mix(dark1.rgb, dark2.rgb, t);
  float l = dot(c, kLuma);
  return mix(c, clamp(dark + (bright.rgb - dark) * l, 0.0, 1.0), bright.a);
}

// A vibrant color matrix (chroma gain, luma weight, lift) applied to c.
vec3 vibrant(vec3 c, vec3 m) {
  float l = dot(c, kLuma);
  return clamp(m.x * (c - l) + m.y * l + m.z, 0.0, 1.0);
}

// The platter's glass at p (inside it): its frost, refracted, blurred by
// `extra` points more (for the resting selection's own blur).
vec3 platter(vec2 p, int taps, float extra) {
  float k = uPass.z * uOptics.z;
  vec4 g = glassAt(p);
  float depth = max(-capsule(p, g), 0.0);
  vec2 n = outward(p, g, uPass.w);
  vec2 q = p - n * kPlatterInner * k * CONTENT.w * sag(depth, kPlatterInnerHeight * k);
  vec3 frosted = extra > 0.0 ? frost(q, extra * k, taps, true) : filtered(inFrost(q));
  // A painted color goes over the frosted backdrop in place of the face.
  return tint(uTints[1].w > 0.5 ? frosted : face(frosted), p, GLASS_TINT);
}

// ---- Lighting.

// The lit rim over color c at p, for glass shaped `shape` scaled by k pixels
// per point: c pushed toward the rim's vibrant color by the rim's alpha.
vec3 rim(vec3 c, vec2 p, vec4 shape, float k, float curvature, vec3 matrix, float amount) {
  float depth = max(-capsule(p, shape), 0.0) / k;
  if (amount <= 0.0 || depth >= kRimHeight + 0.5 / k) {
    return c;
  }
  float u = min(depth / kRimHeight, 1.0);
  float alpha = abs(dot(outward(p, shape, 0.0), kLight)) * (1.0 - curvature * u);
  // The band ends within half a pixel.
  alpha *= clamp((kRimHeight - depth) * k * 2.0 + 0.5, 0.0, 1.0);
  return mix(c, vibrant(c, matrix), alpha * amount);
}

// erfc(x) / 2 for a gaussian edge: Abramowitz and Stegun 7.1.26.
float gaussEdge(float z) {
  float x = abs(z) * 0.70710678;
  float t = 1.0 / (1.0 + 0.3275911 * x);
  float e = t * (0.254829592 + t * (-0.284496736 + t * (1.421413741 +
            t * (-1.453152027 + t * 1.061405429)))) * exp(-x * x);
  return z >= 0.0 ? 0.5 * e : 1.0 - 0.5 * e;
}

// How much a glass shaped `shape` (scaled by k) shades p outside it.
float shade(vec2 p, vec4 shape, float k, vec3 shadow, float reach) {
  float d = capsule(p - vec2(0.0, shadow.x * k), shape) / k;
  if (d >= reach) {
    return 0.0;
  }
  return gaussEdge((d - shadow.z) / shadow.y);
}


// The lens material's darkening of what it reads at q (see kLensTopShade).
float topShade(vec2 q) {
  if (!stage(kShadowStage)) {
    return 1.0;
  }
  float k = uPass.z * uOptics.y;
  return 1.0 - kLensTopShade * (1.0 - shade(q, uLens, k, kLensShadow, 1e4));
}

// The press wash over color c, which UIKit clips to white.
vec3 wash(vec3 c, float amount) {
  float l = dot(c, kLuma);
  return clamp(c + amount * (0.2 * (c - l) + 0.05), 0.0, 1.0);
}

// The fingertip glow's alpha at p: a blurred disk, as a gaussian of the same
// peak and volume (within 2 levels while the finger is down).
float glowAt(vec2 p) {
  vec2 d = p - uGlow.xy;
  return uGlow.w > 0.0 ? uGlow.w * exp(-dot(d, d) * uGlow.z) : 0.0;
}

// How much the glass shades p outside it: the platter, and the glass
// beside it.
float glassShade(vec2 p, float k) {
  float s = shade(p, uPlatter, k, kPlatterShadow, kPlatterShadowReach);
  for (int i = 0; i < GLASS_SHAPES; i++) {
    if (uExtra[i].z > 0.0) {
      s = max(s, shade(p, uExtra[i], k, kPlatterShadow, kPlatterShadowReach));
    }
  }
  return s;
}

// The platter shadow's strength over this backdrop, once per pixel.
float gPlatterShadow = 0.0;

// The platter as what is above it sees it: its glass, lit rim, and the
// press's wash and glow over them.
vec3 litPlatter(vec2 p, int taps, float extra) {
  vec3 c = platter(p, taps, extra);
  if (stage(kRimStage)) {
    c = rim(c, p, glassAt(p), uPass.z * uOptics.z, kPlatterRimCurvature, uRim.xyz, 1.0);
  }
  if (stage(kPressStage)) {
    c = wash(c, kWash * uTouch.w);
    c += glowAt(p) * (1.0 - c);
  }
  return c;
}

// What the lens sees below it, over a pixel's footprint there (the
// mapping's columns j1, j2 for one pixel across and down): the bare
// backdrop is averaged over the footprint, which the lens compresses many
// times near its rim, as UIKit's resampling, stage after stage, smooths it.
// Past the platter, the backdrop lies under the platter's shadow.
vec3 below(vec2 p, vec2 j1, vec2 j2, int taps) {
  if (stage(kPlatterStage) && glassDistance(p) < 0.0) {
    return litPlatter(p, taps, 0.0);
  }
  vec2 a = 0.5 * j1, b = 0.5 * j2;
  vec3 c = 0.25 * (filtered(p - a - b) + filtered(p + a - b) + filtered(p - a + b) +
                   filtered(p + a + b));
  if (gPlatterShadow > 0.0) {
    c *= 1.0 - gPlatterShadow * glassShade(p, uPass.z * uOptics.z);
  }
  return c;
}

// The lens's bounds as UIKit's backdrop captures them: whole pixels, read at
// their centers.
vec4 lensTexels() {
  vec2 lo = ceil(uLens.xy - uLens.zw) + 0.5;
  vec2 hi = ceil(uLens.xy + uLens.zw) - 0.5;
  return vec4(lo, hi);
}

// The lens material's inner refraction: from p, where it looks, pulled
// inward near the edge. UIKit's material refracts at full strength and
// fades in as a whole (see kMaterialFade).
vec2 innerSource(vec2 p) {
  if (!stage(kInnerStage)) {
    return p;
  }
  float k = uPass.z * uOptics.y;
  float depth = max(-capsule(p, uLens), 0.0);
  return p - outward(p, uLens, uPass.w) * kLensInner * k *
                 sag(depth, kLensInnerHeight * k);
}

// The warp: from q, where the lens looks below it, pushed outward by up to
// 9pt at full lift, within the lens's bounds.
vec2 warpSource(vec2 q, float lift) {
  vec2 r = q;
  if (stage(kWarpStage)) {
    float k = uPass.z * uOptics.y;
    float depth = max(-capsule(q, uLens), 0.0);
    r += outward(q, uLens, uPass.w) * kWarp * k * lift *
         sag(depth, kWarpHeight * k);
  }
  vec4 t = lensTexels();
  return clamp(r, t.xy, t.zw);
}

vec2 lensSource(vec2 p, float lift) {
  return warpSource(innerSource(p), lift);
}

// What the lens material has behind it at q: the warped backdrop, with the
// resting selection over it until the lens lifts (UIKit's BackdropView and
// the selection's backdrop, which reads what is below it, above it). UIKit
// renders the warped backdrop as an image that the material then resamples
// and magnifies, so it is averaged here over one pixel of that image.
vec3 base(vec2 q, float lift, int taps) {
  vec2 s = warpSource(q, lift);
  vec2 j1 = warpSource(q + vec2(1.0, 0.0), lift) - s;
  vec2 j2 = warpSource(q + vec2(0.0, 1.0), lift) - s;
  vec3 w = below(s, j1, j2, taps);
  if (lift < 1.0 && stage(kRestStage)) {
    float k = uPass.z * uOptics.z;
    vec3 behind = stage(kPlatterStage) && glassDistance(s) < 0.0
                      ? litPlatter(s, 16, kRestBlur)
                      : frost(s, kRestBlur * k, 16, false);
    // A painted color goes over the glass behind, in place of the
    // selection's own matrix.
    vec3 rest = tint(uTints[6].w > 0.5 ? behind : vibrant(behind, uPill.xyz), q, REST_TINT);
    w = mix(rest, w, lift);
  }
  return w;
}

// ---- Lifted content.

// The tabs' content at x (capture pixels), as laid out in the platter,
// each tab grown about its center by `grow`: the selected tabs (row 0) or
// the normal ones (row 1). Returns the template content (symbols and
// labels; for the selected tabs, colored with the tab's tint from the strip
// under the rows), premultiplied;
// `original` gets the content drawn as it is (badges, images in their own
// colors), from the atlas's rows 2 and 3. UIKit renders templates through
// vibrant color matrices, so of those only the shapes and tints count.
vec4 glyphsAt(vec2 u, float grow, float row, out vec4 original) {
  float first = uTabs.x, spacing = uTabs.y, count = uTabs.z, pitch = uTabs.w;
  float width = uPlatterS.w, height = uPlatterS.z, top = uSelected.y;
  float nearest = spacing > 0.0 ? floor((u.x - first) / spacing + 0.5) : 0.0;
  vec4 sum = vec4(0.0);
  original = vec4(0.0);
  for (int j = -1; j <= 1; j++) {
    float i = nearest + float(j);
    if (i < 0.0 || i >= count) {
      continue;
    }
    vec2 center = vec2(first + i * spacing, top + height * 0.5);
    vec2 v = center + (u - center) / grow;
    float local = v.x - (center.x - width * 0.5);
    float y = v.y - top;
    if (local < 0.0 || local > width || y < 0.0 || y > height) {
      continue;
    }
    vec2 at = vec2(i * pitch + local, y + row * height);
    vec4 t = texture(uContentAtlas, texel(at, uContent.zw));
    if (row < 0.5 && t.a > 0.0) {
      // A template is only a shape: the selected ones take the tab's tint,
      // from the strip under the atlas's rows.
      t.rgb = t.a * texture(uContentAtlas,
                            texel(vec2((i + 0.5) * pitch, 4.0 * height + 0.5), uContent.zw)).rgb;
    }
    sum = t + sum * (1.0 - t.a);
    if (uSelected.w > 0.5) {
      vec4 o = texture(uContentAtlas, texel(at + vec2(0.0, 2.0 * height), uContent.zw));
      original = o + original * (1.0 - o.a);
    }
  }
  return sum;
}

// The same at x (capture pixels), mapped into the tabs' layout through the
// platter's shape, faded and, while it fades, blurred (a 3x3 gaussian over
// the layout, sigma uExtra[4].x points), as UIKit's crossfade blurs it.
vec4 glyphs(vec2 x, float grow, float row, out vec4 original) {
  vec2 b = (x - uContent.xy) / uPass.z;
  vec2 u = uPlatterXf.xy + (b - uPlatterXf.xy - uPlatterXf.zw) / uPlatterS.xy;
  float alpha = CONTENT.x;
  original = vec4(0.0);
  if (alpha <= 0.0) {
    return vec4(0.0);
  }
  float sigma = uExtra[4].x;
  if (sigma < 0.05) {
    vec4 sum = glyphsAt(u, grow, row, original);
    original *= alpha;
    return sum * alpha;
  }
  vec4 sum = vec4(0.0);
  for (int dy = -1; dy <= 1; dy++) {
    for (int dx = -1; dx <= 1; dx++) {
      float w = (dx == 0 ? 0.5 : 0.25) * (dy == 0 ? 0.5 : 0.25);
      vec4 o;
      // Taps at 1.41 sigma give the 3x3 tent the gaussian's variance.
      sum += w * glyphsAt(u + vec2(float(dx), float(dy)) * sigma * 1.41, grow, row, o);
      original += w * o;
    }
  }
  original *= alpha;
  return sum * alpha;
}

// Selected content over what is below it: template content of coverage
// t.a becomes half of what is below plus its tint, plus uSelected.x (UIKit's
// selected vibrant matrix); the rest goes over it as it is.
vec3 selectedOver(vec4 t, vec4 original, vec3 under) {
  vec3 tint = t.a > 0.0 ? t.rgb / t.a : vec3(0.0);
  vec3 lit = uSelected.z > 0.5 ? tint : clamp(0.5 * under + tint + uSelected.x, 0.0, 1.0);
  vec3 c = mix(under, lit, t.a);
  return c * (1.0 - original.a) + original.rgb;
}

// Normal content over what is below it: template content of coverage t.a
// keeps the chroma below at a luma weight plus a lift; the rest goes over
// it as it is.
vec3 symbolsOver(vec4 t, vec4 original, vec3 under) {
  vec3 c = mix(under, vibrant(under, vec3(1.0, uPill.w, uLensRim.w)), t.a);
  return c * (1.0 - original.a) + original.rgb;
}

// The selected tabs at x, each grown by the lift, over what is below them.
vec3 content(vec2 x, float lift, vec3 under) {
  vec4 original;
  vec4 t = glyphs(x, stage(kContentStage) ? 1.0 + kContentGrowth * lift : 1.0, 0.0, original);
  return selectedOver(t, original, under);
}

// The content as the lens shows it directly, over `under`: clipped to the
// lens and lensed once (UIKit's ClearGlassView).
vec3 contentLensed(vec2 q, float lift, vec3 under) {
  vec2 s = q;
  if (stage(kContentStage)) {
    float k = uPass.z * uOptics.y;
    float depth = max(-capsule(q, uLens), 0.0);
    s = q - outward(q, uLens, uPass.w) * kContentLens * k * lift *
                sag(depth, kContentLensHeight * k);
  }
  return capsule(s, uLens) < 0.0 ? content(s, lift, under) : under;
}

// The content as the lens's material shows it, over `under`: lensed once
// more (ContentLensingView).
vec3 contentInMaterial(vec2 p, float lift, vec3 under) {
  if (!stage(kContentStage)) {
    return contentLensed(p, lift, under);
  }
  float k = uPass.z * uOptics.y;
  float depth = max(-capsule(p, uLens), 0.0);
  vec2 r = p - outward(p, uLens, uPass.w) * kContentLens * k * lift *
                   sag(depth, kContentMaterialHeight * k);
  return contentLensed(r, lift, under);
}


// ---- Diagnostics.

float coverage(float d, float px) {
  return clamp(0.5 - d / px, 0.0, 1.0);
}

// A line of `width` pixels along the zero contour of d.
float line(float d, float width) {
  return clamp(width * 0.5 + 0.5 - abs(d), 0.0, 1.0);
}

// Diagonal hatching: marks pixels written by the bar's glass, so any later
// pass that reads rendered glass would show it.
float hatch(vec2 p, float px) {
  return step(0.5, fract((p.x + p.y) / (8.0 * px)));
}

vec4 premul(vec3 c, float a) {
  return vec4(c * a, a);
}

void main() {
  vec2 p = FlutterFragCoord().xy;
  float pass = uPass.x;
  bool diagnostic = uPass.y > 0.5;
  float px = uPass.z;          // one point, in pixels
  float lift = uOptics.x;

  if (pass < 0.5) {
    // ---- Bar pass: the platter's glass, and the backdrop around it under
    // the shadows.
    vec4 g = glassAt(p);
    float d = capsule(p, g);
    float a = coverage(d, 1.0);
    bool shadows = stage(kShadowStage) && !diagnostic;
    if (a <= 0.0 && !shadows) {
      fragColor = vec4(0.0);
      return;
    }
    float kp = px * uOptics.z;
    vec3 c = vec3(0.0);
    if (a > 0.0) {
      c = stage(kPlatterStage) ? platter(p, 0, 0.0) : capture(p);
      if (stage(kRimStage)) {
        c = rim(c, p, g, kp, kPlatterRimCurvature, uRim.xyz, 1.0);
      }
      // The normal tabs (under the lens, the lens covers them), on the
      // platter only, not on glass beside it that grows over it.
      vec4 original;
      vec4 normal = glyphs(p, 1.0, 1.0, original);
      if (capsule(p, uPlatter) > d + 0.001) {
        normal = vec4(0.0);
        original = vec4(0.0);
      }
      c = symbolsOver(normal, original, c);
      if (stage(kPressStage)) {
        c = wash(c, kWash * uTouch.w);
      }
      if (diagnostic) {
        c = mix(c, vec3(1.0, 0.0, 1.0), 0.45 * hatch(p, px));
        // Centered 0.75pt inside the edge, as the canvas's check line is.
        c = mix(c, vec3(1.0, 0.85, 0.0), line(d + 0.75 * px, 1.5 * px));
      }
    }
    if (!shadows) {
      fragColor = premul(c, a);
      return;
    }
    float shaded = 0.0;
    if (a < 1.0) {
      shaded = uRim.w * glassShade(p, kp);
    }
    // The shadow darkens what is below, as black over it: the same as
    // reading it, without the read.
    fragColor = vec4(c * a, a + (1.0 - a) * shaded);
    return;
  }

  if (pass < 1.5) {
    // ---- Lens pass: the resting selection fading into the clear lens, and
    // around it the lens's shadow, over all that is below it (the platter,
    // its tabs, and the press's wash and glow).
    float d = capsule(p, uLens);
    float a = coverage(d, 1.0);
    float k = px * uOptics.y;
    float fade = clamp(kMaterialFade * lift, 0.0, 1.0);
    float shadow = 0.0;
    if (a < 1.0 && fade > 0.0 && stage(kShadowStage) && !diagnostic) {
      shadow = kLensShadowStrength * fade * shade(p, uLens, k, kLensShadow, kLensShadowReach);
    }
    if (a <= 0.0) {
      fragColor = vec4(0.0, 0.0, 0.0, shadow) * CONTENT.y;
      return;
    }
    float depth = max(-d, 0.0);
    vec2 sg = lensSource(p, lift);
    if (stage(kShadowStage)) {
      gPlatterShadow = uRim.w;
    }
    float tone = stage(kInnerStage) ? kLensTone : 1.0;
    // The material fades in quickly as the lens lifts (as UIKit's does),
    // over the base: the resting selection over the warped backdrop.
    // Below the material: the base with the content over it, lensed once.
    vec3 c = fade < 1.0 ? contentLensed(p, lift, base(p, lift, 32)) : vec3(0.0);
    if (fade > 0.0) {
      // The material: the base seen through the inner refraction, the
      // content (lensed again) over it, all dispersed near the edge. A tap
      // past the lens's outline reads the unwarped backdrop, as UIKit's warp
      // is clipped to the outline.
      vec2 inner = innerSource(p);
      vec3 glass = contentInMaterial(p, lift, tint(base(inner, lift, 32) * tone * topShade(inner), p, LENS_TINT));
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
                          : contentInMaterial(at, lift,
                                capsule(at, uLens) < 0.0
                                    ? tint(base(innerSource(at), lift, 16) * tone * topShade(innerSource(at)), at, LENS_TINT)
                                    : below(at, vec2(1.0, 0.0), vec2(0.0, 1.0), 16));
          dispersed += w * s;
        }
        glass = mix(glass, dispersed, spread);
      }
      c = mix(c, glass, fade);
    }
    if (stage(kRimStage)) {
      c = rim(c, p, uLens, k, kLensRimCurvature, uLensRim.xyz, fade);
    }
    if (diagnostic) {
      // Pixels showing content from outside the lens.
      float outside = step(0.0, capsule(sg, uLens));
      c = mix(c, vec3(1.0, 0.5, 0.0), 0.35 * outside);
      c = mix(c, vec3(0.0, 0.9, 1.0), line(d + 0.75 * px, 1.5 * px));
      if (uTouch.z > 0.5) {
        vec2 f = abs(p - uTouch.xy);
        float mark = (f.x < 0.75 * px && f.y < 10.0 * px) ||
                             (f.y < 0.75 * px && f.x < 10.0 * px)
                         ? 1.0
                         : 0.0;
        c = mix(c, vec3(0.1, 1.0, 0.2), mark);
      }
    }
    fragColor = vec4(c * a, a + (1.0 - a) * shadow) * CONTENT.y;
    return;
  }

  if (pass > 2.5) {
    // ---- Frost pass: the platter's light blur, over its heavy one.
    float k = px * uOptics.z;
    float depth = max(-glassDistance(p), 0.0) / k;
    float light = 0.5 - 0.5 * pow(clamp((depth - 1.0) / (kFrostFullDepth - 1.0), 0.0, 1.0), kFrostRamp);
    fragColor = light > 0.0 ? premul(lightFrost(p, kFrostLight * k), light) : vec4(0.0);
    return;
  }

  // ---- Inspector: the capture both passes read, magnified, with the glass
  // field, the lens's sampling region and the finger drawn over it.
  vec2 u = (p - uInspector.xy) / uInspector.zw;
  if (u.x < 0.0 || u.y < 0.0 || u.x > 1.0 || u.y > 1.0) {
    fragColor = vec4(0.0);
    return;
  }
  vec2 q = uWindow.xy + u * uWindow.zw;             // capture position
  float cpx = uWindow.z / uInspector.z;             // capture pixels per output pixel
  vec3 c = capture(q);

  // A 10pt grid, faint.
  vec2 g = abs(fract(q / (10.0 * px) + 0.5) - 0.5) * 10.0 * px;
  float grid = min(g.x, g.y) < 0.6 * cpx ? 1.0 : 0.0;
  c = mix(c, vec3(0.5), 0.25 * grid);

  float dl = capsule(q, uLens);
  float dp = capsule(q, uPlatter);

  // The lens reads within its bounds; the part of them outside the lens is
  // what its rim shows.
  vec2 b = abs(q - uLens.xy) - uLens.zw;
  float db = max(b.x, b.y);
  float band = dl > 0.0 && db <= 0.0 && lift > 0.0 ? 1.0 : 0.0;
  c = mix(c, vec3(1.0, 0.5, 0.0), 0.35 * band);

  // The sampling region: the lens's bounds.
  float dash = step(0.5, fract((q.x + q.y) / (6.0 * px)));
  c = mix(c, vec3(1.0, 0.2, 0.9), dash * line(db / cpx, 1.5));

  // Glass field boundaries.
  c = mix(c, vec3(1.0, 0.85, 0.0), line(dp / cpx, 1.5));
  c = mix(c, vec3(0.0, 0.9, 1.0), line(dl / cpx, 1.5));

  // The finger.
  if (uTouch.z > 0.5) {
    vec2 f = abs(q - uTouch.xy) / cpx;
    float mark = (f.x < 1.0 && f.y < 14.0) || (f.y < 1.0 && f.x < 14.0) ? 1.0 : 0.0;
    c = mix(c, vec3(0.1, 1.0, 0.2), mark);
  }

  // Frame.
  vec2 e = min(u, 1.0 - u) * uInspector.zw;
  if (min(e.x, e.y) < 2.0) {
    c = vec3(1.0);
  }
  fragColor = vec4(c, 1.0);
}
