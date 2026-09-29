#version 460 core

// One shader for every pass over a glass tab bar's shared backdrop: the
// bar's glass, the lens's glass, and a diagnostic inspector. All three read
// the same capture, taken before any of the bar's glass is drawn, and work
// in its coordinates: physical pixels of the pass it was captured from.
//
// Stage 2 (sampling architecture): no final glass appearance. The lens pass
// moves samples outward near its edge, so content from beyond the glass is
// pulled in; the bar and the resting pill get neutral placeholder veils.

#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;        // capture size in pixels (set by the engine)
uniform vec4 uPass;        // pass (0 bar, 1 lens, 2 inspector), diagnostic, pixels per point, ovalization
uniform vec4 uPlatter;     // platter: center.xy, half size.xy
uniform vec4 uLens;        // lens as drawn: center.xy, half size.xy
uniform vec4 uOptics;      // lift progress, displacement at the edge, bevel width, unused
uniform vec4 uTouch;       // finger.xy, pressed, unused
uniform vec4 uInspector;   // inspector on screen: origin.xy, size.xy
uniform vec4 uWindow;      // capture window it shows: origin.xy, size.xy

uniform sampler2D uCapture;

out vec4 fragColor;

// Signed distance to a capsule-cornered box (radius = half the short side).
float capsule(vec2 p, vec4 s) {
  vec2 h = s.zw;
  float r = min(h.x, h.y);
  vec2 q = abs(p - s.xy) - h + r;
  return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

// Outward direction of the capsule's distance, blended by `oval` toward the
// normal of the ellipse inscribed in it.
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
  vec2 o = d / (h * h);
  o = length(o) > 0.0 ? normalize(o) : g;
  vec2 n = mix(g, o, oval);
  return length(n) > 0.0 ? normalize(n) : g;
}

// Where a pixel of the lens samples the capture: moved outward near the
// edge, up to `displacement` at the rim, fading to none a bevel inside.
vec2 lensSource(vec2 p, float displacement, float bevel, float oval) {
  float depth = max(-capsule(p, uLens), 0.0);
  float t = clamp(1.0 - depth / bevel, 0.0, 1.0);
  return p + outward(p, uLens, oval) * displacement * t * t;
}

vec3 capture(vec2 p) {
  return texture(uCapture, p / uSize).rgb;
}

float coverage(float d, float px) {
  return clamp(0.5 - d / px, 0.0, 1.0);
}

// Distance to a line of `width` pixels along the zero contour of d.
float line(float d, float width) {
  return clamp(width * 0.5 + 0.5 - abs(d), 0.0, 1.0);
}

// Diagonal hatching: marks pixels written by the bar's glass, so any later
// pass that reads rendered glass would show it.
float hatch(vec2 p, float px) {
  return step(0.5, fract((p.x + p.y) / (8.0 * px)));
}

vec4 over(vec4 top, vec4 under) {
  return top + under * (1.0 - top.a);
}

vec4 premul(vec3 c, float a) {
  return vec4(c * a, a);
}

void main() {
  vec2 p = FlutterFragCoord().xy;
  float pass = uPass.x;
  bool diagnostic = uPass.y > 0.5;
  float px = uPass.z;          // one point, in pixels
  float oval = uPass.w;
  float lift = uOptics.x;
  float displacement = uOptics.y * lift;
  float bevel = uOptics.z;

  if (pass < 0.5) {
    // ---- Bar pass: the platter's glass.
    float d = capsule(p, uPlatter);
    float a = coverage(d, 1.0);
    if (a <= 0.0) {
      fragColor = vec4(0.0);
      return;
    }
    vec3 c = capture(p);
    if (diagnostic) {
      c = mix(c, vec3(1.0, 0.0, 1.0), 0.45 * hatch(p, px));
      // Centered 0.75pt inside the edge, as the canvas's check line is.
      c = mix(c, vec3(1.0, 0.85, 0.0), line(d + 0.75 * px, 1.5 * px));
    } else {
      c = mix(c, vec3(1.0), 0.30);   // placeholder veil
    }
    fragColor = premul(c, a);
    return;
  }

  if (pass < 1.5) {
    // ---- Lens pass: the pill at rest, the lens when lifted.
    float d = capsule(p, uLens);
    float a = coverage(d, 1.0);
    if (a <= 0.0) {
      fragColor = vec4(0.0);
      return;
    }
    vec2 s = lensSource(p, displacement, bevel, oval);
    vec3 c = capture(s);
    if (diagnostic) {
      // Pixels showing content from outside the lens.
      float outside = step(0.0, capsule(s, uLens));
      c = mix(c, vec3(1.0, 0.5, 0.0), 0.35 * outside);
      c = mix(c, vec3(0.0, 0.9, 1.0), line(d + 0.75 * px, 1.5 * px));
    } else {
      // Placeholder: the resting pill is dimmed, the lens is not.
      c = mix(c * 0.78, c, lift);
    }
    if (uTouch.z > 0.5) {
      vec2 f = abs(p - uTouch.xy);
      float mark = (f.x < 0.75 * px && f.y < 10.0 * px) ||
                           (f.y < 0.75 * px && f.x < 10.0 * px)
                       ? 1.0
                       : 0.0;
      if (diagnostic) {
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

  // The band outside the lens that its edge samples from.
  float band = dl > 0.0 && dl <= displacement ? 1.0 : 0.0;
  c = mix(c, vec3(1.0, 0.5, 0.0), 0.35 * band);

  // The sampling region: the lens grown by its reach.
  vec4 region = vec4(uLens.xy, uLens.zw + displacement);
  float dr = capsule(q, region);
  float dash = step(0.5, fract((q.x + q.y) / (6.0 * px)));
  c = mix(c, vec3(1.0, 0.2, 0.9), dash * line(dr / cpx, 1.5));

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
