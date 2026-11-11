#version 460 core

// A vibrant label on glass (UIKit draws a glass button's title and image
// through a vibrantColorMatrix): where the label's glyphs are, what is
// under them (the glass) through a color matrix, plus the label's color.
//
// UIKit's matrix (every glass button style, iOS 26.5) is 1.5 times the
// color less 1.4 times its luma, offset by 0.9: the label shows 0.69 of the
// matrix on the glass under it, plus 0.9 times its own color (a black label
// takes the glass's colors, deeper and darker; a white one on blue glass
// turns pale cyan). Fitted to its buttons over color blocks, within 15
// levels. The label's alpha (a disabled label's 0.3) mixes it with the
// glass.

#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;     // capture size in pixels (set by the engine)
uniform vec4 uRect;     // the label mask's box in capture pixels: left, top, width, height
uniform vec4 uMatrix;   // color gain, luma weight, scale, strength
uniform vec4 uColor;    // the label's color, times UIKit's offset (rgb)

uniform sampler2D uCapture;
uniform sampler2D uMask;

out vec4 fragColor;

const vec3 kLuma = vec3(0.2126, 0.7152, 0.0722);

void main() {
  vec2 p = FlutterFragCoord().xy;
  vec2 uv = p / uSize;
  vec3 c = texture(uCapture, uv).rgb;
  vec2 m = (p - uRect.xy) / uRect.zw;
  float a = 0.0;
  if (m.x >= 0.0 && m.y >= 0.0 && m.x <= 1.0 && m.y <= 1.0) {
    a = texture(uMask, m).a * uMatrix.w;
  }
  vec3 v = clamp(uMatrix.z * (uMatrix.x * c - uMatrix.y * dot(c, kLuma)) + uColor.rgb,
                0.0, 1.0);
  fragColor = vec4(mix(c, v, a), 1.0);
}
