import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

/// One piece of glass: a rectangle whose corners are circular arcs.
///
/// With [radius] at half the shorter side it is a capsule, the shape of iOS
/// tab bars, their selection pill and their lens. (Measured on the iOS 26 tab
/// bar, the capsule ends follow a circular arc to within 0.2pt: at full
/// rounding, continuous corners reduce to plain arcs.)
@immutable
class GlassShape {
  GlassShape(this.rect, {double? radius})
    : radius = math.min(radius ?? rect.shortestSide / 2, rect.shortestSide / 2);

  final Rect rect;
  final double radius;

  /// Signed distance from [p] to the outline: negative inside.
  double distance(Offset p) {
    final double qx = (p.dx - rect.center.dx).abs() - rect.width / 2 + radius;
    final double qy = (p.dy - rect.center.dy).abs() - rect.height / 2 + radius;
    final double outside = math.sqrt(
      math.pow(math.max(qx, 0), 2) + math.pow(math.max(qy, 0), 2),
    );
    return outside + math.min(math.max(qx, qy), 0) - radius;
  }

  /// Unit direction in which [distance] grows fastest at [p], blended by
  /// [ovalization] (0 to 1) toward the normal of the ellipse inscribed in
  /// [rect].
  ///
  /// A capsule's own normals are straight up or down along its sides and
  /// only turn around the ends; the blend makes them turn continuously all
  /// the way round, as UIKit's glass shapes do (an ovalization of 0.5 on the
  /// iOS 26 tab bar lens).
  Offset normal(Offset p, {double ovalization = 0}) {
    final Offset own = _gradient(p);
    if (ovalization <= 0) {
      return own;
    }
    final Offset d = p - rect.center;
    final double a = rect.width / 2, b = rect.height / 2;
    final Offset oval = _unit(Offset(d.dx / (a * a), d.dy / (b * b)));
    return _unit(Offset.lerp(own, oval, ovalization)!);
  }

  Offset _gradient(Offset p) {
    final double sx = p.dx < rect.center.dx ? -1 : 1;
    final double sy = p.dy < rect.center.dy ? -1 : 1;
    final double qx = (p.dx - rect.center.dx).abs() - rect.width / 2 + radius;
    final double qy = (p.dy - rect.center.dy).abs() - rect.height / 2 + radius;
    if (qx > 0 && qy > 0) {
      return _unit(Offset(sx * qx, sy * qy));
    }
    if (qx > 0 || qy > 0) {
      return qx > qy ? Offset(sx, 0) : Offset(0, sy);
    }
    // Inside the core rectangle: the nearest side wins.
    return qx > qy ? Offset(sx, 0) : Offset(0, sy);
  }

  static Offset _unit(Offset v) {
    final double l = v.distance;
    return l == 0 ? Offset.zero : v / l;
  }

  @override
  bool operator ==(Object other) =>
      other is GlassShape && other.rect == rect && other.radius == radius;

  @override
  int get hashCode => Object.hash(rect, radius);

  @override
  String toString() => 'GlassShape($rect, radius: $radius)';
}

/// Glass shapes that flow into one another where they come close, the way
/// iOS 26 merges glass inside a `GlassEffectContainer` (like drops of water).
///
/// Shapes that are separate pieces of glass, like a tab bar and the lens
/// lifted above it, belong in separate fields: the lens meets the bar at a
/// sharp crease, not a fillet.
@immutable
class GlassField {
  const GlassField(this.shapes, {this.smoothness = 6});

  final List<GlassShape> shapes;

  /// How far apart, in logical pixels, two shapes start to flow together.
  final double smoothness;

  double distance(Offset p) {
    var d = double.infinity;
    for (final GlassShape shape in shapes) {
      d = _smoothMin(d, shape.distance(p), smoothness);
    }
    return d;
  }

  bool contains(Offset p) => distance(p) <= 0;

  /// The smallest rectangle outside of which [distance] is positive.
  Rect get bounds => shapes.isEmpty
      ? Rect.zero
      : shapes
            .map((GlassShape s) => s.rect)
            .reduce((Rect a, Rect b) => a.expandToInclude(b));

  // Polynomial smooth minimum: exact min once a and b differ by more than k.
  static double _smoothMin(double a, double b, double k) {
    if (a.isInfinite) {
      return b;
    }
    if (k <= 0) {
      return math.min(a, b);
    }
    final double h = math.max(k - (a - b).abs(), 0) / k;
    return math.min(a, b) - h * h * k / 4;
  }
}
