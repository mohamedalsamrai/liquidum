import 'dart:math' as math;

/// A damped harmonic oscillator, stepped with its exact solution so that the
/// motion does not depend on the frame rate.
///
/// Configured the way UIKit describes springs: [response] is the period of
/// the undamped oscillation in seconds, and [dampingRatio] is 1 for critical
/// damping and less than 1 for a spring that overshoots.
class GlassSpring {
  GlassSpring({
    required this.response,
    required this.dampingRatio,
    double value = 0,
    this.tolerance = 1e-3,
  }) : value = value,
       target = value;

  /// A spring given as mass, stiffness and damping, like
  /// `BSSpringAnimationSettings` on iOS.
  GlassSpring.physical({
    required double mass,
    required double stiffness,
    required double damping,
    double value = 0,
    this.tolerance = 1e-3,
  }) : response = 2 * math.pi / math.sqrt(stiffness / mass),
       dampingRatio = damping / (2 * math.sqrt(stiffness * mass)),
       value = value,
       target = value;

  double response;
  double dampingRatio;

  /// How close to [target], in the units of [value], counts as settled.
  final double tolerance;

  double value;
  double target;

  /// In units of [value] per second.
  double velocity = 0;

  bool get isSettled =>
      (value - target).abs() <= tolerance && velocity.abs() <= tolerance * 10;

  /// Changes [response] and [dampingRatio] without disturbing the motion.
  void configure(double response, double dampingRatio) {
    this.response = response;
    this.dampingRatio = dampingRatio;
  }

  /// Jumps to [to] and stops there.
  void snap(double to) {
    value = to;
    target = to;
    velocity = 0;
  }

  /// Advances the motion by [dt] seconds.
  void step(double dt) {
    if (dt <= 0) {
      return;
    }
    if (isSettled) {
      value = target;
      velocity = 0;
      return;
    }
    final double w = 2 * math.pi / response;
    final double z = dampingRatio;
    final double x0 = value - target;
    final double v0 = velocity;
    double x, v;
    if ((z - 1).abs() < 1e-4) {
      // Critically damped (UIKit's settings land within rounding of 1).
      final double decay = math.exp(-w * dt);
      final double b = v0 + w * x0;
      x = (x0 + b * dt) * decay;
      v = (b - w * (x0 + b * dt)) * decay;
    } else if (z < 1) {
      final double wd = w * math.sqrt(1 - z * z);
      final double decay = math.exp(-z * w * dt);
      final double c = math.cos(wd * dt), s = math.sin(wd * dt);
      final double b = (v0 + z * w * x0) / wd;
      x = decay * (x0 * c + b * s);
      v = decay * (-z * w * (x0 * c + b * s) + wd * (b * c - x0 * s));
    } else {
      final double r = w * math.sqrt(z * z - 1);
      final double r1 = -z * w + r, r2 = -z * w - r;
      final double c2 = (v0 - r1 * x0) / (r2 - r1);
      final double c1 = x0 - c2;
      final double e1 = math.exp(r1 * dt), e2 = math.exp(r2 * dt);
      x = c1 * e1 + c2 * e2;
      v = c1 * r1 * e1 + c2 * r2 * e2;
    }
    value = target + x;
    velocity = v;
  }
}
