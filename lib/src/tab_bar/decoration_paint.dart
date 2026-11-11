import 'dart:math' as math;

import 'package:flutter/painting.dart';

import 'decoration.dart';
import 'style.dart';
import 'tint.dart';

// How a GlassDecoration is painted, shared by the tab bar and the liquid
// lens on its own: its shadows around and inside the glass's shape, and its
// color or gradient as the shaders' tint inputs.

Paint _shadowPaint(BoxShadow shadow, double opacity) {
  final paint = Paint()
    ..color = shadow.color.withValues(alpha: shadow.color.a * opacity);
  if (shadow.blurSigma > 0) {
    paint.maskFilter = MaskFilter.blur(BlurStyle.normal, shadow.blurSigma);
  }
  return paint;
}

/// How far [shadow] reaches past its shape.
double glassShadowReach(BoxShadow shadow) =>
    2 * shadow.blurRadius +
    shadow.spreadRadius.abs() +
    shadow.offset.distance +
    2;

/// Drop shadows of [shape], around it only: the glass shows what is under
/// it, a shadow there included.
void paintGlassShadows(
  Canvas canvas,
  RRect shape,
  List<BoxShadow>? shadows,
  double opacity,
) {
  if (shadows == null || shadows.isEmpty || opacity <= 0) {
    return;
  }
  final double reach = shadows.map(glassShadowReach).reduce(math.max);
  canvas
    ..save()
    ..clipPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(shape.outerRect.inflate(reach))
        ..addRRect(shape),
    );
  for (final BoxShadow shadow in shadows) {
    canvas.drawRRect(
      shape.inflate(shadow.spreadRadius).shift(shadow.offset),
      _shadowPaint(shadow, opacity),
    );
  }
  canvas.restore();
}

/// Shadows cast inward from [shape]'s edge, over it, as inset shadows: the
/// shape's outside, its edge moved by the offset and in by the spread,
/// blurred into it.
void paintGlassInnerShadows(
  Canvas canvas,
  RRect shape,
  List<BoxShadow>? shadows,
  double opacity,
) {
  if (shadows == null || shadows.isEmpty || opacity <= 0) {
    return;
  }
  canvas
    ..save()
    ..clipRRect(shape);
  for (final BoxShadow shadow in shadows) {
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(shape.outerRect.inflate(glassShadowReach(shadow)))
        ..addRRect(shape.deflate(shadow.spreadRadius).shift(shadow.offset)),
      _shadowPaint(shadow, opacity),
    );
  }
  canvas.restore();
}

/// A decoration's color or gradient as the shaders take it: its tint at the
/// gradient's start and end, the gradient's axis within [shape] (capture
/// pixels), and whether it is painted rather than tinted; a color is both
/// ends at once. Colors resolve for the [dark] appearance.
typedef GlassDecorationTint = (GlassTint, GlassTint, Offset, Offset, bool);

GlassDecorationTint decorationTint(
  GlassDecoration decoration,
  Rect shape, {
  required TextDirection textDirection,
  required bool dark,
}) {
  final GlassFill fill = decoration.fill;
  final bool paint = fill == GlassFill.paint;
  GlassTint tint(Color? color) {
    final Color? resolved = color == null
        ? null
        : GlassTabBarStyle.resolve(color, dark: dark);
    return paint
        ? GlassTint.paint(resolved)
        : GlassTint(resolved, darkAppearance: dark);
  }

  final LinearGradient? gradient = decoration.gradient;
  if (gradient == null || gradient.colors.isEmpty) {
    final GlassTint t = tint(decoration.color);
    return (t, t, Offset.zero, Offset.zero, paint);
  }
  return (
    tint(gradient.colors.first),
    tint(gradient.colors.last),
    gradient.begin.resolve(textDirection).withinRect(shape),
    gradient.end.resolve(textDirection).withinRect(shape),
    paint,
  );
}
