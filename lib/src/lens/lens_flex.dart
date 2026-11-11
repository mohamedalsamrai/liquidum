import 'dart:math' as math;
import 'dart:ui' show Size;

import '../tab_bar/spring.dart';

/// UIKit's liquid lens as a soft body: the flex of the tab bar's lens, the
/// switch's and slider's thumbs and the segmented control's selection as
/// they move (iOS 26.5).
///
/// Every change in the lens's velocity on screen, smoothed over 20ms as
/// UIKit's velocity integrator does, kicks one state m, which springs back
/// on UIKit's loupe flex spring (157.9/25.13, critically damped). m, taken
/// within ±0.46, sets the lens's scale and drift: x scales by 1 + 0.6m and
/// the lens drifts [driftPerState] times m points against the motion; y
/// scales by 1 - m while m is small, flattening at most about 40% and
/// bulging at most 28%. The result eases in on a slightly overdamped
/// spring. Fitted to UIKit's flex state over nine gestures on the tab bar;
/// the controls' lenses flex the same way (a 150pt/s start stretches them
/// about 1.03, a tapped segment's slide up to 1.14), their drift in
/// proportion to their width.
class LensFlex {
  /// A soft body whose drift is [driftPerState] points per unit of m: the
  /// tab bar's lens drifts -14.8.
  LensFlex({required this.driftPerState});

  /// The soft body of a lens [width] points wide: its drift scales with
  /// its width (the bar's -14.8pt for its pill; 0.3pt per 1.03 stretch
  /// for a 37pt thumb, 1.0 for a 129pt segment).
  LensFlex.forWidth(double width) : driftPerState = width * driftPerWidth;

  // UIKit's numbers.
  static const double gain = 0.0173;
  static const double smoothing = 0.02;
  static const double limit = 0.46;
  static const double scaleX = 0.6;
  static const double flattenKnee = 0.3;
  static const double flattenLimit = 0.4;
  static const double bulgeLimit = 0.28;

  /// The drift per unit of m per point of the lens's width: the bar's
  /// -14.8 for a 92.5pt pill.
  static const double driftPerWidth = -0.16;

  static const (double, double) ease = (0.314, 1.15);

  /// Points of drift per unit of m, against the motion.
  double driftPerState;

  final GlassSpring _state = GlassSpring.physical(
    mass: 1,
    stiffness: 157.91367,
    damping: 25.132741,
    tolerance: 1e-5,
  );
  final GlassSpring _x = GlassSpring(
    response: 0.314,
    dampingRatio: 1.15,
    value: 1,
    tolerance: 1e-5,
  );
  final GlassSpring _y = GlassSpring(
    response: 0.314,
    dampingRatio: 1.15,
    value: 1,
    tolerance: 1e-5,
  );
  final GlassSpring _shift = GlassSpring(
    response: 0.314,
    dampingRatio: 1.15,
    tolerance: 1e-3,
  );
  double _smoothedVelocity = 0;
  double _kicked = 0;

  /// The flex's springs: the state, the x and y scales and the drift, for
  /// an owner that steps its springs together.
  List<GlassSpring> get springs => <GlassSpring>[_state, _x, _y, _shift];

  bool get isSettled => springs.every((GlassSpring s) => s.isSettled);

  /// The soft-body state m.
  double get state => _state.value;

  /// The lens's scale (x, y) and drift (points, along the motion's axis), as
  /// drawn.
  Size get scale => Size(_x.value, _y.value);
  double get drift => _shift.value;

  /// Sets the scale's and drift's targets from the state: once per frame,
  /// before its springs are stepped (as the bar does).
  void aim() {
    final double m = _state.value.clamp(-limit, limit);
    _state.target = 0;
    _x
      ..configure(ease.$1, ease.$2)
      ..target = 1 + scaleX * m;
    _y
      ..configure(ease.$1, ease.$2)
      ..target = m >= 0
          ? 1 - _flatten(m)
          : 1 + bulgeLimit * _tanh(-m / bulgeLimit);
    _shift
      ..configure(ease.$1, ease.$2)
      ..target = driftPerState * m;
  }

  /// Feeds the lens's velocity on screen (points per second) over a step
  /// of [dt] seconds, after the springs were stepped by it: a change in it
  /// kicks the state.
  void kick(double velocity, double dt, {bool reduceMotion = false}) {
    _smoothedVelocity +=
        (velocity - _smoothedVelocity) * (1 - math.exp(-dt / smoothing));
    final double v = _smoothedVelocity;
    if (!reduceMotion) {
      _state.velocity += gain * (v - _kicked);
    }
    _kicked = v;
  }

  /// Advances the flex by [dt] seconds under a lens moving at [velocity]
  /// (points per second), in slices of at most 4ms, for an owner without
  /// springs of its own to step alongside.
  void advance(double dt, double velocity, {bool reduceMotion = false}) {
    if (dt <= 0) {
      return;
    }
    aim();
    final int slices = math.max(1, (dt / 0.004).ceil());
    final double h = dt / slices;
    for (var i = 0; i < slices; i++) {
      for (final GlassSpring s in springs) {
        s.step(h);
      }
      kick(velocity, h, reduceMotion: reduceMotion);
    }
  }

  // How much the lens flattens for m > 0: m itself up to a knee, then
  // easing toward a limit.
  static double _flatten(double m) {
    if (m <= flattenKnee) {
      return m;
    }
    const double room = flattenLimit - flattenKnee;
    return flattenKnee + room * _tanh((m - flattenKnee) / room);
  }

  static double _tanh(double x) {
    if (x > 20) {
      return 1;
    }
    if (x < -20) {
      return -1;
    }
    final double e = math.exp(2 * x);
    return (e - 1) / (e + 1);
  }
}
