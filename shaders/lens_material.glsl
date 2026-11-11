// UIKit's liquid lens (`_UILiquidLensView`), shared by the tab bar's shader
// (backdrop.frag, whose lens pass draws the bar's selection) and the lens on
// its own (lens.frag, for the lens controls): its numbers, its shape, its
// warp and inner refraction, its rim, shadow and top shade, and the stage
// bits that switch its optics off one at a time. Moved here from
// backdrop.frag as they were, so the two cannot drift. The including shader
// declares, before including glass_material.glsl and then this:
//   uniform vec4 uPass;    // .z pixels per point, .w ovalization
//   uniform vec4 uLens;    // the lens as drawn: center.xy, half size.zw (capture pixels)
//   uniform vec4 uOptics;  // .y the lens's scale (its points per layout point), .w stages
// Pixels are capture pixels; lengths in points are scaled by k, the pixels
// per point of the lens's own points (uPass.z * uOptics.y).

// ---- UIKit's numbers, in the lens's own points.

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

// The resting selection blurs the glass behind it again (a gaussian blur,
// radius 2 at quarter scale), then applies a color matrix (uPill).
const float kRestBlur = 2.22;

// UIKit fades the lens's material in at four times the lift progress.
const float kMaterialFade = 4.0;

// The lens's rim: lit as the platter's (see rimLight), with its own
// curvature.
const float kLensRimCurvature = 0.8;
// The lens's shadow (from its glass filter): outside the lens, what is below
// is multiplied by 1 - strength * (a gaussian edge of the outline moved
// down); (offset, sigma, center) in points, nothing past the reach. The
// strength is the filter's opacity * (0.093 + 0.966 fill), the fill black.
// Fits UIKit's within 0.3 levels.
const vec3 kLensShadow = vec3(7.0, 5.49, 0.05);
const float kLensShadowStrength = 0.1086;
const float kLensShadowReach = 9.21;
// Inside, the lens's material darkens what it reads where its shadow's
// edge is not: most just inside its top edge, and none past 15pt in (by
// this much over what is below, wherever the shadow there would be none).
// Fitted to UIKit's lifted lens over white, gray and a position code; a
// shadow opacity of 0.111 in its glass filter is the likely source.
const float kLensTopShade = 0.06;

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
  return roundBox(p, s, min(s.z, s.w));
}

// Outward direction of the capsule's distance, blended by `oval` toward the
// direction of the point in the capsule's normalized coordinates: UIKit's
// ovalization, which this matches to within 1.3 degrees (median) over its
// lens's displacement field.
vec2 outward(vec2 p, vec4 s, float oval) {
  return roundOutward(p, s, min(s.z, s.w), oval);
}

// ---- Lighting.

// The lit rim over color c at p, for glass shaped `shape` scaled by k pixels
// per point: c pushed toward the rim's vibrant color by the rim's alpha.
vec3 rim(vec3 c, vec2 p, vec4 shape, float k, float curvature, vec3 matrix, float amount) {
  float depth = max(-capsule(p, shape), 0.0) / k;
  if (amount <= 0.0 || depth >= kRimHeight + 0.5 / k) {
    return c;
  }
  return rimLight(c, depth, outward(p, shape, 0.0), k, curvature, matrix, amount);
}

// How much a glass shaped `shape` (scaled by k) shades p outside it.
float shade(vec2 p, vec4 shape, float k, vec3 shadow, float reach) {
  return shadeAt(capsule(p - vec2(0.0, shadow.x * k), shape) / k, shadow, reach);
}

// The lens material's darkening of what it reads at q (see kLensTopShade).
float topShade(vec2 q) {
  if (!stage(kShadowStage)) {
    return 1.0;
  }
  float k = uPass.z * uOptics.y;
  return 1.0 - kLensTopShade * (1.0 - shade(q, uLens, k, kLensShadow, 1e4));
}

// ---- Sampling.

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

// The inner refraction with an amount and a height of its own (points): the
// lens controls' lenses refract by their lifted height (lens.frag). The
// bar's innerSource above is kept as it was.
vec2 innerSourceWith(vec2 p, float inner, float height) {
  if (!stage(kInnerStage)) {
    return p;
  }
  float k = uPass.z * uOptics.y;
  float depth = max(-capsule(p, uLens), 0.0);
  return p - outward(p, uLens, uPass.w) * inner * k * sag(depth, height * k);
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

// Coverage of a pixel `px` wide by the glass at signed distance d.
float coverage(float d, float px) {
  return clamp(0.5 - d / px, 0.0, 1.0);
}
