import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// How a [GlassDecoration]'s color or gradient fills the glass.
enum GlassFill {
  /// As iOS tints glass (`UIGlassEffect.tintColor`): the glass takes the
  /// color, deeper where it is darker and as it is where it is white.
  tint,

  /// Painted as it is over the frosted backdrop, in place of the glass's own
  /// color, at its alpha: as a translucent fill over a background blur in a
  /// design tool. An opaque color or gradient shows exactly.
  paint,
}

/// How a piece of the tab bar's glass is decorated: the bar's own glass, the
/// selection at rest, or the lens it lifts into while moving. Like a
/// [BoxDecoration], on glass.
///
/// ```dart
/// GlassDecoration(
///   gradient: LinearGradient(colors: [Color(0xFFD82789), Color(0xFF7257A8)]),
///   shadows: [BoxShadow(color: Color(0x1A000000), blurRadius: 6, offset: Offset(0, 1))],
///   innerShadows: [BoxShadow(color: Color(0x40FFFFFF), blurRadius: 1, spreadRadius: 1)],
/// )
/// ```
@immutable
class GlassDecoration {
  const GlassDecoration({
    this.color,
    this.gradient,
    this.fill = GlassFill.tint,
    this.shadows,
    this.innerShadows,
  });

  /// Colors the glass, as [fill] says: by default as iOS tints glass
  /// (`UIGlassEffect.tintColor`). The color's alpha sets how strongly.
  final Color? color;

  /// Colors the glass with a gradient across it instead of [color], the same
  /// way: from its first color at [LinearGradient.begin] to its last at
  /// [LinearGradient.end] (colors between them are not used).
  final LinearGradient? gradient;

  /// How [color] or [gradient] fills the glass: tinted as iOS tints glass
  /// (the default), or painted as it is, as in a design.
  final GlassFill fill;

  /// Drop shadows, around the glass and not under it (it would show through).
  /// For the bar's glass, they replace UIKit's own shadow; an empty list
  /// removes it.
  final List<BoxShadow>? shadows;

  /// Shadows cast inward from the glass's edge, over it: a [BoxShadow]'s
  /// offset moves it as an inset shadow's, and its spread grows it inward.
  /// A light color makes a rim of light.
  final List<BoxShadow>? innerShadows;

  /// This decoration with [color] when it has neither a color nor a
  /// gradient.
  GlassDecoration withColor(Color? color) =>
      color == null || this.color != null || gradient != null
      ? this
      : GlassDecoration(
          color: color,
          shadows: shadows,
          innerShadows: innerShadows,
        );

  @override
  bool operator ==(Object other) =>
      other is GlassDecoration &&
      other.color == color &&
      other.gradient == gradient &&
      other.fill == fill &&
      listEquals(other.shadows, shadows) &&
      listEquals(other.innerShadows, innerShadows);

  @override
  int get hashCode => Object.hash(
    color,
    gradient,
    fill,
    shadows == null ? null : Object.hashAll(shadows!),
    innerShadows == null ? null : Object.hashAll(innerShadows!),
  );
}
