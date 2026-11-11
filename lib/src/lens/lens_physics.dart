import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../tab_bar/spring.dart';

/// UIKit's liquid lens variants: the small lens of its switch and slider
/// thumbs, and the large one of its tab bar (`_UILiquidLensView`'s small
/// and large settings, iOS 26.5).
enum LensVariant {
  /// Lifts on a spring of stiffness 541.54 and damping 29.09 (8% over at
  /// 0.17s), falls back on 157.91 / 17.59.
  small,

  /// Lifts and falls on 631.65 / 50.27, critically damped in 0.25s: the
  /// tab bar's.
  large,
}

/// The lift of a liquid lens under a finger, advanced one frame at a time,
/// for the controls that draw one ([LiquidLens]): a frame after a touch the
/// lens lifts into clear glass on its variant's lift spring, holds while the
/// finger does, and falls back on its unlift spring once the finger leaves;
/// a quick tap keeps it lifted for [hangTime] after the touch. The lens's
/// bounds [growth] follows the lift, more slowly while it hangs after a tap
/// (UIKit's loupe spring), as the tab bar's does.
///
/// Times are seconds on one clock, the frame clock given to [tick]
/// (`SchedulerBinding.currentSystemFrameTimeStamp`); a touch without a time
/// counts from the next tick. Notifies listeners after every tick.
///
/// The lens's flex (its stretch and drift along a drag) and its following of
/// the finger are the controls' own, as each UIKit control moves its lens
/// differently; [LiquidLens.flexScale] and [LiquidLens.drift] take them.
class LensLift extends ChangeNotifier {
  /// A lift on [variant]'s springs, or on its own: [liftSpring] and
  /// [unliftSpring] as (stiffness, damping) with mass 1. [hangTime] is how
  /// long a quick tap keeps the lens lifted after the finger leaves (the
  /// bar's 0.22s; UIKit's controls do not hang: 0), and [minimumLift] how
  /// long after a touch the lens stays lifted at least (the switch's tap
  /// lifts it for about 0.15s).
  LensLift({
    this.variant = LensVariant.small,
    (double, double)? liftSpring,
    (double, double)? unliftSpring,
    this.hangTime = defaultHangTime,
    this.minimumLift = 0,
  }) : _liftSpring = liftSpring == null
           ? (variant == LensVariant.small ? _smallLift : _largeLift)
           : _spring(liftSpring.$1, liftSpring.$2),
       _unliftSpring = unliftSpring == null
           ? (variant == LensVariant.small ? _smallUnlift : _largeLift)
           : _spring(unliftSpring.$1, unliftSpring.$2) {
    _lift.configure(_liftSpring.$1, _liftSpring.$2);
    _growth.configure(_liftSpring.$1, _liftSpring.$2);
  }

  final LensVariant variant;

  /// How long a quick tap keeps the bar's lens lifted after the finger
  /// leaves.
  static const double defaultHangTime = 0.22;

  /// How long a quick tap keeps this lens lifted after the finger leaves.
  final double hangTime;

  /// How long after a touch the lens stays lifted at least (seconds).
  final double minimumLift;

  final (double, double) _liftSpring;
  final (double, double) _unliftSpring;

  /// UIKit starts the lift a frame after the touch.
  static const double liftDelay = 0.015;

  /// Reduce Motion, as UIKit honors it: the lens does not lift.
  bool reduceMotion = false;

  // Springs as UIKit configures them (mass 1; stiffness, damping), as
  // (response, damping ratio).
  static (double, double) _spring(double stiffness, double damping) => (
    2 * math.pi / math.sqrt(stiffness),
    damping / (2 * math.sqrt(stiffness)),
  );
  static final (double, double) _smallLift = _spring(541.54208, 29.088821);
  static final (double, double) _smallUnlift = _spring(157.91367, 17.592919);
  static final (double, double) _largeLift = _spring(631.654682, 50.265482);
  static final (double, double) _hangGrowth = (_spring(157.91367, 0).$1, 1.0);

  final GlassSpring _lift = GlassSpring(
    response: 0.25,
    dampingRatio: 1,
    tolerance: 1e-4,
  );
  final GlassSpring _growth = GlassSpring(
    response: 0.25,
    dampingRatio: 1,
    tolerance: 1e-4,
  );

  bool _down = false;
  double? _pressTime;
  double _hangUntil = double.negativeInfinity;
  double? _now;
  final List<(bool, double?)> _pending = <(bool, double?)>[];

  /// Whether a finger holds the lens.
  bool get pressed => _down;

  /// The lift progress, 0 (resting) to 1 (lifted): [LiquidLens.lift].
  double get lift => _lift.value.clamp(0.0, 1.0);

  /// How far the lens's bounds have grown toward their lifted size, 0 to 1
  /// (a little below 0 as the unlift spring undershoots), for the controls
  /// to grow their thumb by as UIKit's grow (8pt a side on the tab bar).
  double get growth => _growth.value;

  /// Whether anything is still moving (or pressed, or hanging).
  bool get isActive =>
      _down ||
      _pending.isNotEmpty ||
      (_now ?? double.negativeInfinity) < _hangUntil ||
      !_lift.isSettled ||
      !_growth.isSettled;

  /// A finger came down, at [time] if known.
  void down({double? time}) => _pending.add((true, time));

  /// The finger left (or the touch was cancelled), at [time] if known.
  void up({double? time}) => _pending.add((false, time));

  /// Advances the lift to [now] (seconds). Returns whether anything is still
  /// moving.
  bool tick(double now) {
    final double start = _now ?? now;
    var t = start;
    for (final (bool down, double? time) in _pending) {
      final double at = (time ?? now).clamp(t, now);
      _advance(t, at);
      _apply(down, at);
      t = at;
    }
    _pending.clear();
    _advance(t, now);
    _now = now;
    notifyListeners();
    return isActive;
  }

  void _apply(bool down, double t) {
    if (down) {
      _down = true;
      _pressTime = t;
      _hangUntil = double.negativeInfinity;
    } else if (_down) {
      _down = false;
      final double held = t - (_pressTime ?? t);
      _hangUntil = math.max(
        held < hangTime ? t + hangTime : t,
        (_pressTime ?? t) + minimumLift,
      );
    }
  }

  // Steps from [t0] to [t1], splitting where the lift starts and where the
  // hang ends, so that the springs turn at the moment and not at a frame.
  void _advance(double t0, double t1) {
    if (t1 <= t0) {
      return;
    }
    final double? pressed = _pressTime;
    final List<double> splits = <double>[
      if (pressed != null && _down) pressed + liftDelay,
      if (!_down) _hangUntil,
    ]..removeWhere((double s) => s <= t0 || s >= t1);
    splits.sort();
    var a = t0;
    for (final double b in <double>[...splits, t1]) {
      _step(a, b - a);
      a = b;
    }
  }

  void _step(double t, double dt) {
    final double since = _pressTime == null ? double.infinity : t - _pressTime!;
    final bool hanging = !_down && t < _hangUntil;
    final bool lifted =
        !reduceMotion && ((_down && since >= liftDelay) || hanging);
    final double target = lifted ? 1 : (_down ? _lift.target : 0);
    final (double r, double z) = target > 0.5 ? _liftSpring : _unliftSpring;
    _lift
      ..configure(r, z)
      ..target = target;
    final (double gr, double gz) = hanging ? _hangGrowth : (r, z);
    _growth
      ..configure(gr, gz)
      ..target = target;
    // Slices of at most 4ms, as the bar steps its springs.
    final int slices = math.max(1, (dt / 0.004).ceil());
    for (var i = 0; i < slices; i++) {
      _lift.step(dt / slices);
      _growth.step(dt / slices);
    }
  }
}
