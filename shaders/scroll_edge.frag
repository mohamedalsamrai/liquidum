#version 460 core

// UIKit's scroll-edge effect (iOS 26's soft edge, UIKit.ScrollEdgeEffectView)
// over the content under a bar.
//
// Its mask is a soft step at the edge line: m = Phi(d / 18pt), d the
// distance past the line into the bar (a black shadow of radius 18 in
// UIKit). Under it, three things, each through the mask:
// - a variable blur (UIKit's variableBlur, its mask remapped to
//   1.25 m - 0.25): a Gaussian of up to 1.72pt, in full where the mask is
//   (fitted on 8pt stripes at rest);
// - with the system light, over darker content, black at 0.25;
// - otherwise a wash toward the page's background: 0.8 with the system
//   light, and with it dark 0.85, 0.6 or 0.3 as the content is darker or
//   lighter.

#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;     // capture size in pixels (set by the engine)
uniform vec4 uEdge;     // edge line y (capture px), direction (+1: the bar is above), mask sigma (px), blur sigma (px)
uniform vec4 uAmount;   // blur weight, black, wash, unused
uniform vec4 uWash;     // the wash's color (rgb)

uniform sampler2D uCapture;

out vec4 fragColor;

// The standard normal's distribution function (a tanh fit, within 0.001).
float phi(float z) {
  return 0.5 * (1.0 + tanh(0.7978846 * (z + 0.044715 * z * z * z)));
}

vec3 at(vec2 p) {
  vec2 uv = p / uSize;
#ifdef IMPELLER_TARGET_OPENGLES
  uv.y = 1.0 - uv.y;
#endif
  return texture(uCapture, uv).rgb;
}

void main() {
  vec2 p = FlutterFragCoord().xy;
  float m = phi(uEdge.y * (uEdge.x - p.y) / uEdge.z);
  vec3 c = at(p);
  float w = uAmount.x * clamp(1.25 * m - 0.25, 0.0, 1.0);
  float sigma = uEdge.w * w;
  if (sigma > 0.25) {
    // A Gaussian sampled on a 5 x 5 grid, a sigma apart.
    vec3 sum = vec3(0.0);
    float total = 0.0;
    for (int i = -2; i <= 2; i++) {
      for (int j = -2; j <= 2; j++) {
        float k = exp(-0.5 * float(i * i + j * j));
        sum += k * at(p + vec2(float(i), float(j)) * sigma);
        total += k;
      }
    }
    c = sum / total;
  }
  c *= 1.0 - uAmount.y * m;
  c = mix(c, uWash.rgb, uAmount.z * m);
  fragColor = vec4(c, 1.0);
}
