// UIKit's glass material, shared by the tab bar's shader (backdrop.frag) and
// Glass's (glass.frag): its geometry, its sampling of the backdrop capture,
// and its color, rim and shadow. The including shader declares `uSize` (the
// capture's size in pixels) and `uCapture` (the capture) before including it.
// Pixels are capture pixels; lengths in points are scaled by k, the pixels
// per point.

const vec3 kLuma = vec3(0.2126, 0.7152, 0.0722);

// The glass filter's SDR holding tone.
const float kGlassTone = 0.97;

// The rim: a key light from up-left and a fill from down-right at equal
// amounts light a 1pt band inside the edge by |n.l| (see the rim below).
const vec2 kLight = vec2(0.70710678, 0.70710678);
const float kRimHeight = 1.0;

// ---- Geometry.

// Signed distance to the box of half size s.zw about s.xy, its corners of
// radius r (a capsule when r is half its short side).
float roundBox(vec2 p, vec4 s, float r) {
  vec2 q = abs(p - s.xy) - s.zw + r;
  return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

// Apple's continuous corners (`cornerCurve = .continuous`), as an inset of
// the outline from roundBox's circular corners: the outline is pulled in
// where a corner's arc meets a straight side, by up to 0.017 r, over 0.52 r
// of the side and about 30 degrees of the arc; a side too short for that
// (a capsule's ends) has none. Measured from UIKit's glass silhouettes at
// radii 12 to 50 (iOS 26.5), within 0.1pt.
float continuousInset(vec2 p, vec4 s, float r) {
  if (r <= 0.0) {
    return 0.0;
  }
  // From the corner circle's center, folded into one quadrant: +x toward
  // the side edge, +y toward the top edge.
  vec2 v = abs(p - s.xy) - (s.zw - r);
  // How much of each junction's curve the straight lengths leave room for.
  vec2 room = clamp(2.0 * (s.zw - r) / (1.057 * r), 0.0, 1.0);
  float inset = 0.0;
  if (v.y > 0.0) {
    // The junction with the top edge, at v = (0, r).
    if (v.x < 0.0) {
      float u = min(-v.x / r / 0.52, 1.0);
      inset += room.x * 0.0128 * (1.0 - u) * (1.0 - u);
    } else {
      float phi = atan(v.x, v.y);
      float w = max(1.0 - phi / 0.55, 0.0);
      inset += room.x * 0.0128 * w * w * (1.0 + 10.3 * phi);
    }
  }
  if (v.x > 0.0) {
    // The junction with the side edge, at v = (r, 0).
    if (v.y < 0.0) {
      float u = min(-v.y / r / 0.52, 1.0);
      inset += room.y * 0.0128 * (1.0 - u) * (1.0 - u);
    } else {
      float phi = atan(v.y, v.x);
      float w = max(1.0 - phi / 0.55, 0.0);
      inset += room.y * 0.0128 * w * w * (1.0 + 10.3 * phi);
    }
  }
  return inset * r;
}

// The signed distance to a box with Apple's continuous corners.
float continuousBox(vec2 p, vec4 s, float r) {
  return roundBox(p, s, r) + continuousInset(p, s, r);
}

// Outward direction of the box's distance, blended by `oval` toward the
// direction of the point in the box's normalized coordinates (x / half
// width, y / half height): the ovalization of UIKit's glass shapes.
vec2 roundOutward(vec2 p, vec4 s, float r, float oval) {
  vec2 d = p - s.xy;
  vec2 h = s.zw;
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

// Texture coordinates for a point in an image that is `size` big, top-left
// origin. Impeller's GLES backend keeps the textures it renders to upside
// down.
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

// ---- Color.

// A vibrant color matrix (chroma gain, luma weight, lift) applied to c.
vec3 vibrant(vec3 c, vec3 m) {
  float l = dot(c, kLuma);
  return clamp(m.x * (c - l) + m.y * l + m.z, 0.0, 1.0);
}

// The glass's face over its frosted backdrop c: the luma mapped from the
// black point face.x to the white point face.y, the chroma kept at `chroma`,
// and a fill of gray face.w mixed in at face.z, under the holding tone.
vec3 glassFace(vec3 c, vec4 face, float chroma) {
  float l = dot(c, kLuma);
  vec3 f = face.x + (face.y - face.x) * l + (c - l) * chroma;
  return clamp(kGlassTone * mix(f, vec3(face.w), face.z), 0.0, 1.0);
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

// ---- Lighting.

// The lit rim over color c, `depth` points inside the edge whose outward
// direction is n, for glass scaled by k pixels per point: c pushed toward
// the rim's vibrant color by the rim's alpha. (The caller skips it past
// kRimHeight + 0.5 / k.)
vec3 rimLight(vec3 c, float depth, vec2 n, float k, float curvature, vec3 matrix, float amount) {
  float u = min(depth / kRimHeight, 1.0);
  float alpha = abs(dot(n, kLight)) * (1.0 - curvature * u);
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

// How much glass shades a point `d` points outside its outline moved down
// by shadow.x: a gaussian edge of sigma shadow.y about shadow.z, nothing
// past `reach`.
float shadeAt(float d, vec3 shadow, float reach) {
  if (d >= reach) {
    return 0.0;
  }
  return gaussEdge((d - shadow.z) / shadow.y);
}

// The press wash over color c, which UIKit clips to white.
vec3 wash(vec3 c, float amount) {
  float l = dot(c, kLuma);
  return clamp(c + amount * (0.2 * (c - l) + 0.05), 0.0, 1.0);
}
