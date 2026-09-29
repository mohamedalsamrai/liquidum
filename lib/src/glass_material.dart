import 'dart:math' as math;
import 'dart:ui' show Color, Offset, lerpDouble;

import 'package:flutter/foundation.dart';

/// The physical description of a piece of glass.
///
/// Lengths are in logical pixels. A material says nothing about shape or
/// position; a [Glass] surface supplies those.
///
/// The presets are fitted to iOS 26 glass, measured in the iOS 26.5 simulator
/// against ramp, stripe and color backgrounds.
@immutable
class GlassMaterial {
  const GlassMaterial({
    this.refraction = 32,
    this.falloff = 6.5,
    this.endRefraction = 79,
    this.endFalloff = 32,
    this.dispersion = 0.012,
    this.zoom = 1,
    this.blur = 3.8,
    this.saturation = 1.25,
    this.response = 0.40,
    this.lift = 0.593,
    this.tint = const Color(0x00000000),
    this.specular = 0.7,
    this.lightAngle = -math.pi * 7 / 9,
    this.lightFocus = 0,
    this.shadowOpacity = 0.07,
    this.shadowSoftness = 16,
    this.shadowOffset = const Offset(0, 8),
  });

  /// Frosted glass for bars and controls, light appearance.
  static const regular = GlassMaterial();

  /// Frosted glass for bars and controls, dark appearance.
  static const regularDark = GlassMaterial(
    blur: 4.5,
    saturation: 0.92,
    response: 0.5,
    lift: 0.075,
    specular: 0.155,
  );

  /// Nearly transparent, strongly lensing glass, light appearance. This is
  /// what a tab bar's selection turns into while it is pressed.
  static const clear = GlassMaterial(
    refraction: 50,
    falloff: 4.5,
    endRefraction: 0,
    dispersion: 0.025,
    zoom: 0.95,
    blur: 1.5,
    saturation: 1,
    response: 1.04,
    lift: 0.078,
    lightFocus: 1,
  );

  /// [clear], dark appearance.
  static const clearDark = GlassMaterial(
    refraction: 50,
    falloff: 4.5,
    endRefraction: 0,
    dispersion: 0.025,
    zoom: 0.95,
    blur: 1.5,
    saturation: 1,
    response: 1.04,
    lift: 0.078,
    specular: 0.2,
    lightFocus: 1,
  );

  /// Glass with no effect at all, to animate a surface in from or out to.
  static const identity = GlassMaterial(
    refraction: 0,
    endRefraction: 0,
    dispersion: 0,
    blur: 0,
    saturation: 1,
    response: 1,
    lift: 0,
    specular: 0,
    shadowOpacity: 0,
  );

  /// How far inward, at the very edge, the glass looks for what it shows.
  ///
  /// Negative values look outward instead, pulling in the surroundings.
  final double refraction;

  /// Distance from the edge over which [refraction] decays by a factor of e.
  final double falloff;

  /// How far inward along its length an elongated shape looks at its ends.
  ///
  /// Scaled by how elongated the shape is; no effect on circles and squares.
  final double endRefraction;

  /// Distance from the ends over which [endRefraction] decays by a factor of e.
  final double endFalloff;

  /// Scale of what the glass shows, about its center. Below 1 the glass shows
  /// more than what is directly under it, pulling in its surroundings.
  final double zoom;

  /// Relative spread of [refraction] between the red and blue channels.
  final double dispersion;

  /// Gaussian blur sigma applied to the backdrop before refraction.
  final double blur;

  /// Chroma gain applied after [response] and [lift].
  final double saturation;

  /// How much of the backdrop comes through: each channel is scaled by this,
  /// then [lift]ed. Together they act as the frost veil.
  final double response;

  /// Light added after [response], in 0..1.
  final double lift;

  /// Color mixed over the result; its alpha is the mix amount.
  final Color tint;

  /// How far the rim light mixes towards white where it is strongest.
  final double specular;

  /// Direction towards the light in radians, clockwise from the +x axis with
  /// y pointing down. See [lightFocus].
  final double lightAngle;

  /// How much the rim light gathers along [lightAngle]: 0 lights the rim
  /// evenly all the way round (as on iOS bars), 1 lights it only along the
  /// light axis, on both sides.
  final double lightFocus;

  final double shadowOpacity;

  /// Sigma of the soft shadow cast by the slab.
  final double shadowSoftness;

  final Offset shadowOffset;

  GlassMaterial copyWith({
    double? refraction,
    double? falloff,
    double? endRefraction,
    double? endFalloff,
    double? dispersion,
    double? zoom,
    double? blur,
    double? saturation,
    double? response,
    double? lift,
    Color? tint,
    double? specular,
    double? lightAngle,
    double? lightFocus,
    double? shadowOpacity,
    double? shadowSoftness,
    Offset? shadowOffset,
  }) {
    return GlassMaterial(
      refraction: refraction ?? this.refraction,
      falloff: falloff ?? this.falloff,
      endRefraction: endRefraction ?? this.endRefraction,
      endFalloff: endFalloff ?? this.endFalloff,
      dispersion: dispersion ?? this.dispersion,
      zoom: zoom ?? this.zoom,
      blur: blur ?? this.blur,
      saturation: saturation ?? this.saturation,
      response: response ?? this.response,
      lift: lift ?? this.lift,
      tint: tint ?? this.tint,
      specular: specular ?? this.specular,
      lightAngle: lightAngle ?? this.lightAngle,
      lightFocus: lightFocus ?? this.lightFocus,
      shadowOpacity: shadowOpacity ?? this.shadowOpacity,
      shadowSoftness: shadowSoftness ?? this.shadowSoftness,
      shadowOffset: shadowOffset ?? this.shadowOffset,
    );
  }

  static GlassMaterial lerp(GlassMaterial a, GlassMaterial b, double t) {
    if (identical(a, b)) {
      return a;
    }
    double d(double x, double y) => lerpDouble(x, y, t)!;
    return GlassMaterial(
      refraction: d(a.refraction, b.refraction),
      falloff: d(a.falloff, b.falloff),
      endRefraction: d(a.endRefraction, b.endRefraction),
      endFalloff: d(a.endFalloff, b.endFalloff),
      dispersion: d(a.dispersion, b.dispersion),
      zoom: d(a.zoom, b.zoom),
      blur: d(a.blur, b.blur),
      saturation: d(a.saturation, b.saturation),
      response: d(a.response, b.response),
      lift: d(a.lift, b.lift),
      tint: Color.lerp(a.tint, b.tint, t)!,
      specular: d(a.specular, b.specular),
      lightAngle: d(a.lightAngle, b.lightAngle),
      lightFocus: d(a.lightFocus, b.lightFocus),
      shadowOpacity: d(a.shadowOpacity, b.shadowOpacity),
      shadowSoftness: d(a.shadowSoftness, b.shadowSoftness),
      shadowOffset: Offset.lerp(a.shadowOffset, b.shadowOffset, t)!,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is GlassMaterial &&
        other.refraction == refraction &&
        other.falloff == falloff &&
        other.endRefraction == endRefraction &&
        other.endFalloff == endFalloff &&
        other.dispersion == dispersion &&
        other.zoom == zoom &&
        other.blur == blur &&
        other.saturation == saturation &&
        other.response == response &&
        other.lift == lift &&
        other.tint == tint &&
        other.specular == specular &&
        other.lightAngle == lightAngle &&
        other.lightFocus == lightFocus &&
        other.shadowOpacity == shadowOpacity &&
        other.shadowSoftness == shadowSoftness &&
        other.shadowOffset == shadowOffset;
  }

  @override
  int get hashCode => Object.hash(
    refraction,
    falloff,
    endRefraction,
    endFalloff,
    dispersion,
    zoom,
    blur,
    saturation,
    response,
    lift,
    tint,
    specular,
    lightAngle,
    lightFocus,
    shadowOpacity,
    shadowSoftness,
    shadowOffset,
  );
}
