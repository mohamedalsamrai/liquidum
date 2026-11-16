#version 460 core

// UIKit's popover shadow (iOS 26.5): _UIRoundedRectShadowView, a soft
// rounded box under the popover's glass reaching 150pt past it, drawn
// through a vibrantColorMatrix: where the shadow is (its image's alpha a),
// what is under it becomes c + a A (M c + o - c), with A = 1 - w.c. It
// darkens colors by up to a quarter, white by a tenth, and leaves black
// alone; the glass over it sees it too.
//
// The shadow image's alpha, by the distance d (points) outside the glass's
// box with corners of 12pt: 1 within 40pt inside, 0 from 150pt out, and a
// polynomial between (fitted to UIKit's image within 0.01 along its sides,
// 0.04 in its corners: .research/popshadow.py).

#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;     // capture size in pixels (set by the engine)
uniform vec4 uBox;      // the glass's box: center, half size (capture px)
uniform vec4 uParams;   // pixels per point, strength (0 to 1), unused, unused

uniform sampler2D uCapture;

out vec4 fragColor;

const float kCorner = 12.0;

// UIKit's matrix (its inputColorMatrix, rows r, g, b; and its alpha row).
const mat3 kMatrix = mat3(0.6719, -0.0938, -0.0938,   // column r
                          -0.1719, 0.5781, -0.1719,   // column g
                          0.0781, 0.0781, 0.8281);    // column b
const vec3 kOffset = vec3(0.0, 0.0156, 0.0);
const vec3 kAlpha = vec3(0.2344, 0.4531, 0.0938);

float profile(float d) {
  if (d <= -40.0) {
    return 1.0;
  }
  if (d >= 150.0) {
    return 0.0;
  }
  float u = (d + 40.0) / 190.0;
  float f = ((((((22.94999 * u - 67.65253) * u + 69.73943) * u - 25.48864) * u - 0.74147) * u +
              0.21536) * u + 0.99173);
  return clamp(f, 0.0, 1.0);
}

void main() {
  vec2 p = FlutterFragCoord().xy;
  vec3 c = texture(uCapture, p / uSize).rgb;
  float k = uParams.x;
  float r = kCorner * k;
  vec2 q = abs(p - uBox.xy) - uBox.zw + r;
  float d = (length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r) / k;
  float a = profile(d) * uParams.y;
  vec3 v = clamp(kMatrix * c + kOffset, 0.0, 1.0);
  float alpha = clamp(1.0 - dot(kAlpha, c), 0.0, 1.0);
  fragColor = vec4(c + a * alpha * (v - c), 1.0);
}
