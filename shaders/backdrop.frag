#version 460 core

// One shader for every pass over a glass tab bar's shared backdrop: the
// bar's glass, the lens's glass, and a diagnostic inspector. All three read
// the same capture, taken before any of the bar's glass is drawn, and work
// in its coordinates: physical pixels of the pass it was captured from.
//
// The optics are UIKit's, from the layers of its own tab bar on iOS 26.5:
// parameters read from the live layer tree and each stage measured on its
// own over position-coded backdrops.
//
// - The platter (regular glass) refracts inward near its edge, frosts (more
//   toward its middle line), and lifts luma toward white while keeping 73%
//   of the chroma.
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

#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;        // capture size in pixels (set by the engine)
uniform vec4 uPass;        // pass (0 bar, 1 lens, 2 inspector), diagnostic, pixels per point, ovalization
uniform vec4 uPlatter;     // platter: center.xy, half size.xy
uniform vec4 uLens;        // lens as drawn: center.xy, half size.xy
uniform vec4 uOptics;      // lift progress, lens scale, platter scale, stages (debug: bit mask)
uniform vec4 uTouch;       // finger.xy, pressed, unused
uniform vec4 uInspector;   // inspector on screen: origin.xy, size.xy
uniform vec4 uWindow;      // capture window it shows: origin.xy, size.xy
uniform vec4 uContent;     // the bar's origin in capture pixels.xy, the content atlas's size in points.zw
uniform vec4 uTabs;        // first tab's center x, spacing, count, atlas slot pitch (points)
uniform vec4 uPlatterXf;   // platter transform: center.xy, drift.xy (points)
uniform vec4 uPlatterS;    // platter scale.xy, unused, atlas slot width (points)

uniform sampler2D uCapture;
uniform sampler2D uContentAtlas;  // the tabs in the selected style, one per slot

out vec4 fragColor;

// ---- UIKit's numbers, in the glass's own points.

// Lens: displacementMap amount at full lift (liftedDisplacement) and the
// height of its CASDFGlassDisplacementEffect.
const float kWarp = 9.0;
const float kWarpHeight = 36.0;
// Lens glassBackground: inner refraction amount and height, SDR holding tone.
const float kLensInner = 17.5;
const float kLensInnerHeight = 7.0;
const float kLensTone = 0.97;
// Lens glassForeground (aberration amount 3.68, offset 38.9, angle -15
// degrees): the image is dispersed over seven taps along a vector that grows
// with the position (x / half width, y / half height); red takes the three
// taps toward one end (1:2:3), blue the mirror, green the middle five
// (1:2:3:2:1). Mixed in fully at the edge, not at all 14pt in.
const float kAberrationDepth = 14.0;
const mat2 kAberration = mat2(-1.499, 2.235, 5.925, 0.706);
// Platter glassBackground: inner refraction, and frost. The frost mixes a
// heavily blurred backdrop into a lightly filtered one (its quarter-scale
// capture), fully at the platter's middle line and half at its edge
// (inputBlurDistance/Opacity: 1 at 31pt in, 0.5 at 1pt in); the two blurs
// are gaussian sigmas in points (as this shader samples them), fitted to
// its frost over stripes.
const float kPlatterInner = 49.6;
const float kPlatterInnerHeight = 15.5;
const float kFrostSharp = 1.0;
const float kFrostDeep = 2.9;
const float kFrostFullDepth = 31.0;
const vec3 kFace = vec3(0.8627, 0.1294, 0.727);
// The resting selection blurs the glass behind it again (gaussianBlur,
// radius 2 at quarter scale), then applies a color matrix (columns: from
// red, green, blue).
const float kRestBlur = 2.22;
const mat3 kRest = mat3(1.185, -0.015, -0.015, -0.05, 1.15, -0.05, -0.005, -0.005, 1.195);
const float kRestOffset = -0.2;
// Lifted content (UIKit's contentWrapperDisplacement): the selected tabs, seen
// in the lens, are lensed by two displacement maps of this amount at full
// lift (one of height 11.2, then one of height 14 in the material), each
// pulling inward near the edge.
// UIKit also scales each selected tab by 1.16 about its center at full lift.
const float kContentLens = 17.5;
const float kContentLensHeight = 11.2;
const float kContentMaterialHeight = 14.0;
const float kContentGrowth = 0.16;
// The lens's material is faded in by UIKit's opacityPair filter, at four
// times the lift progress.
const float kMaterialFade = 4.0;

const vec3 kLuma = vec3(0.2126, 0.7152, 0.0722);

// Stages, for comparing them one at a time (GlassTabBar's debugOptics).
const float kWarpStage = 1.0;
const float kInnerStage = 2.0;
const float kDispersionStage = 4.0;
const float kPlatterStage = 8.0;
const float kRestStage = 16.0;
const float kContentStage = 32.0;

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
// width, y / half height): UIKit's gradientOvalization, which this matches
// to within 1.3 degrees (median) over its lens's displacement field.
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

// UIKit's glass displacement profile: the sag of a circular arc, 1 at the
// edge, 0 at `height` in.
float sag(float depth, float height) {
  float u = clamp(1.0 - depth / height, 0.0, 1.0);
  return 1.0 - sqrt(1.0 - u * u);
}

// ---- Sampling.

vec3 capture(vec2 p) {
  return texture(uCapture, p / uSize).rgb;
}

// Gaussian frost around p: a Vogel spiral out to 2.5 sigma.
vec3 frost(vec2 p, float sigma, int taps) {
  vec3 sum = vec3(0.0);
  float total = 0.0;
  for (int i = 0; i < 64; i++) {
    if (i >= taps) {
      break;
    }
    float t = (float(i) + 0.5) / float(taps);
    float r = sqrt(t) * 2.5;
    float a = float(i) * 2.39996323;
    float w = exp(-0.5 * r * r);
    sum += capture(p + vec2(cos(a), sin(a)) * r * sigma) * w;
    total += w;
  }
  return sum / total;
}

vec3 face(vec3 c) {
  float l = dot(c, kLuma);
  return clamp(kFace.x + kFace.y * l + kFace.z * (c - l), 0.0, 1.0);
}

// The platter's glass at p (inside it), blurred by `extra` points more (for
// the resting selection's own blur).
vec3 platter(vec2 p, int taps, float extra) {
  float k = uPass.z * uOptics.z;
  float depth = max(-capsule(p, uPlatter), 0.0);
  vec2 n = outward(p, uPlatter, uPass.w);
  vec2 q = p - n * kPlatterInner * k * sag(depth, kPlatterInnerHeight * k);
  float deep = clamp(0.5 + 0.5 * (depth / k - 1.0) / (kFrostFullDepth - 1.0), 0.5, 1.0);
  float sharp = sqrt(kFrostSharp * kFrostSharp + extra * extra) * k;
  float heavy = sqrt(kFrostDeep * kFrostDeep + extra * extra) * k;
  vec3 light = frost(q, sharp, extra > 0.0 ? taps : 8);
  return face(mix(light, frost(q, heavy, taps), deep));
}

// What the lens sees below it, over a pixel's footprint there (the
// mapping's columns j1, j2 for one pixel across and down): the bare
// backdrop is averaged over the footprint, which the lens compresses many
// times near its rim, as UIKit's resampling, stage after stage, smooths it.
vec3 below(vec2 p, vec2 j1, vec2 j2, int taps) {
  if (stage(kPlatterStage) && capsule(p, uPlatter) < 0.0) {
    return platter(p, taps, 0.0);
  }
  vec2 a = 0.5 * j1, b = 0.5 * j2;
  return 0.25 * (capture(p - a - b) + capture(p + a - b) + capture(p - a + b) +
                 capture(p + a + b));
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
    vec3 behind = stage(kPlatterStage) && capsule(s, uPlatter) < 0.0
                      ? platter(s, 32, kRestBlur)
                      : frost(s, kRestBlur * k, 32);
    vec3 rest = clamp(kRest * behind + kRestOffset, 0.0, 1.0);
    w = mix(rest, w, lift);
  }
  return w;
}

// ---- Lifted content.

// The tabs in the selected style at x (capture pixels), as laid out in the
// platter, each scaled about its center by the lift (premultiplied).
vec4 content(vec2 x, float lift) {
  vec2 b = (x - uContent.xy) / uPass.z;
  vec2 u = uPlatterXf.xy + (b - uPlatterXf.xy - uPlatterXf.zw) / uPlatterS.xy;
  float first = uTabs.x, spacing = uTabs.y, count = uTabs.z, pitch = uTabs.w;
  float width = uPlatterS.w;
  float nearest = spacing > 0.0 ? floor((u.x - first) / spacing + 0.5) : 0.0;
  vec4 sum = vec4(0.0);
  for (int j = -1; j <= 1; j++) {
    float i = nearest + float(j);
    if (i < 0.0 || i >= count) {
      continue;
    }
    vec2 center = vec2(first + i * spacing, uContent.w * 0.5);
    float grow = stage(kContentStage) ? 1.0 + kContentGrowth * lift : 1.0;
    vec2 v = center + (u - center) / grow;
    float local = v.x - (center.x - width * 0.5);
    if (local < 0.0 || local > width || v.y < 0.0 || v.y > uContent.w) {
      continue;
    }
    vec4 t = texture(uContentAtlas, vec2(i * pitch + local, v.y) / uContent.zw);
    sum = t + sum * (1.0 - t.a);
  }
  return sum;
}

// The content as the lens shows it directly: clipped to the lens and lensed
// once (UIKit's ClearGlassView).
vec4 contentLensed(vec2 q, float lift) {
  if (!stage(kContentStage)) {
    return capsule(q, uLens) < 0.0 ? content(q, lift) : vec4(0.0);
  }
  float k = uPass.z * uOptics.y;
  float depth = max(-capsule(q, uLens), 0.0);
  vec2 s = q - outward(q, uLens, uPass.w) * kContentLens * k * lift *
                   sag(depth, kContentLensHeight * k);
  return capsule(s, uLens) < 0.0 ? content(s, lift) : vec4(0.0);
}

// The content as the lens's material shows it: lensed once more
// (ContentLensingView).
vec4 contentInMaterial(vec2 p, float lift) {
  if (!stage(kContentStage)) {
    return contentLensed(p, lift);
  }
  float k = uPass.z * uOptics.y;
  float depth = max(-capsule(p, uLens), 0.0);
  vec2 r = p - outward(p, uLens, uPass.w) * kContentLens * k * lift *
                   sag(depth, kContentMaterialHeight * k);
  return contentLensed(r, lift);
}

vec3 over(vec4 top, vec3 under) {
  return top.rgb + under * (1.0 - top.a);
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
    // ---- Bar pass: the platter's glass.
    float d = capsule(p, uPlatter);
    float a = coverage(d, 1.0);
    if (a <= 0.0) {
      fragColor = vec4(0.0);
      return;
    }
    vec3 c = stage(kPlatterStage) ? platter(p, 64, 0.0) : capture(p);
    if (diagnostic) {
      c = mix(c, vec3(1.0, 0.0, 1.0), 0.45 * hatch(p, px));
      // Centered 0.75pt inside the edge, as the canvas's check line is.
      c = mix(c, vec3(1.0, 0.85, 0.0), line(d + 0.75 * px, 1.5 * px));
    }
    fragColor = premul(c, a);
    return;
  }

  if (pass < 1.5) {
    // ---- Lens pass: the resting selection fading into the clear lens.
    float d = capsule(p, uLens);
    float a = coverage(d, 1.0);
    if (a <= 0.0) {
      fragColor = vec4(0.0);
      return;
    }
    float k = px * uOptics.y;
    float depth = max(-d, 0.0);
    vec2 sg = lensSource(p, lift);
    float tone = stage(kInnerStage) ? kLensTone : 1.0;
    // The material fades in quickly as the lens lifts (UIKit's opacityPair),
    // over the base: the resting selection over the warped backdrop.
    float fade = clamp(kMaterialFade * lift, 0.0, 1.0);
    // Below the material: the base with the content over it, lensed once.
    vec3 c = fade < 1.0 ? over(contentLensed(p, lift), base(p, lift, 32)) : vec3(0.0);
    if (fade > 0.0) {
      // The material: the base seen through the inner refraction, the
      // content (lensed again) over it, all dispersed near the edge. A tap
      // past the lens's outline reads the unwarped backdrop, as UIKit's warp
      // is clipped to the outline.
      vec3 glass = over(contentInMaterial(p, lift),
                        base(innerSource(p), lift, 32) * tone);
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
                          : over(contentInMaterial(at, lift),
                                 capsule(at, uLens) < 0.0
                                     ? base(innerSource(at), lift, 16) * tone
                                     : below(at, vec2(1.0, 0.0), vec2(0.0, 1.0), 16));
          dispersed += w * s;
        }
        glass = mix(glass, dispersed, spread);
      }
      c = mix(c, glass, fade);
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
    fragColor = premul(c, a);
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
