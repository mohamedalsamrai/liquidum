import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/rendering.dart' show Matrix4;

import 'spring.dart';

/// Everything that moves in a glass tab bar, advanced one frame at a time:
/// the platter (the bar's own glass), the lens that selects a tab, and the
/// states that drive the glass optics.
///
/// Geometry is in the bar's layout coordinates, in logical pixels. The lens
/// and the tab content live inside the platter and share its transform
/// ([platterTransform]): the platter swells while pressed and stretches and
/// drifts toward the finger.
///
/// The model and its numbers come from UIKit's own tab bar on the iOS 26.5
/// simulator: its lens and flex state logged every frame under scripted
/// touches (398×62pt bar, four tabs), and its settings read at runtime
/// (`_UILiquidLensViewSpec`, `_UIFlexInteractionSpec`). Where UIKit's lens
/// trails the finger through a spring, this lens follows it exactly.
class GlassTabBarPhysics {
  GlassTabBarPhysics({required int count, required int selectedIndex})
    : assert(count > 0),
      _count = count,
      _selected = selectedIndex;

  /// Called at the end of every [tick], for debugging and measurement.
  static void Function(GlassTabBarPhysics physics, double now)? debugOnTick;

  // ---------------------------------------------------------------- layout

  /// Gap between the platter's edge and the resting pill of an end tab.
  static const double inset = 4;

  /// How much the lens outgrows the pill when lifted, on each side.
  static const double liftOutset = 8;

  Size _size = Size.zero;
  int _count;
  int _selected;

  Size get size => _size;
  int get count => _count;

  /// The tab that the lens rests on when released.
  int get selectedIndex => _selected;

  /// Width of the resting pill: wider than the spacing between tabs, so
  /// neighbouring pills would overlap (107.5pt for four tabs in 398pt).
  double get pillWidth =>
      ((_size.width - 2 * inset) / _count + 10).clamp(0, _size.width);

  double get pillHeight => math.max(_size.height - 2 * inset, 0);

  /// Center of tab [index]: the end tabs' pills sit [inset] from the ends,
  /// and the others are evenly spaced between them.
  double tabCenter(int index) {
    if (_count == 1) {
      return _size.width / 2;
    }
    final double first = inset + pillWidth / 2;
    return first + index * (_size.width - 2 * first) / (_count - 1);
  }

  int nearestTab(double x) {
    var best = 0;
    for (var i = 1; i < _count; i++) {
      if ((tabCenter(i) - x).abs() < (tabCenter(best) - x).abs()) {
        best = i;
      }
    }
    return best;
  }

  /// Lays the bar out at [size] with [count] tabs.
  void layout(Size size, int count) {
    final bool first = _size == Size.zero;
    _size = size;
    _count = count;
    _selected = _selected.clamp(0, count - 1);
    if (first || !isActive) {
      _anchor = _clampToBar(tabCenter(_selected));
      _offset.snap(0);
      _shadow.snap(_anchor);
      _history.clear();
      _anchorLog.clear();
    } else if (_touch == null) {
      _anchor = tabCenter(_selected);
      _anchorLog.clear();
    }
  }

  // The lens may carry the resting pill up to the platter's edge, not past.
  double _clampToBar(double x) {
    final double half = pillWidth / 2;
    if (_size.width <= 2 * half) {
      return _size.width / 2;
    }
    return x.clamp(half, _size.width - half);
  }

  // ---------------------------------------------------------------- springs

  // Springs as UIKit configures them (mass 1; stiffness, damping).
  static double _z(double stiffness, double damping) =>
      damping / (2 * math.sqrt(stiffness));
  static double _r(double stiffness) => 2 * math.pi / math.sqrt(stiffness);

  // The platter swells 3.55% while pressed. It rises on the small lens's
  // lift spring (541.5/29.09: overshoot 8%) and falls on the large flex
  // spring (304.6/20.94: undershoot 9%).
  static const double pressedScale = 1.0355;
  static final (double, double) _swell = (
    _r(541.54208),
    _z(541.54208, 29.088821),
  );
  static final (double, double) _unswell = (
    _r(304.61742),
    _z(304.61742, 20.943951),
  );
  final GlassSpring _scale = GlassSpring(
    response: 0.27,
    dampingRatio: 0.625,
    value: 1,
    tolerance: 1e-5,
  );

  // The platter stretches toward the finger, keeping its area, and drifts
  // the same way: k grows 2.77e-5 per point the finger has moved and
  // 8.2e-5 per point it is outside the platter; the drift is 1.075·k times
  // the platter's length along that axis.
  static const double _stretchPerPoint = 2.77e-5;
  static const double _stretchPerOutsidePoint = 8.2e-5;
  static const double _driftPerStretch = 1.075;
  static const (double, double) _stretchFollow = (0.314, 1.0);
  final GlassSpring _stretchX = GlassSpring(
    response: 0.314,
    dampingRatio: 1,
    tolerance: 1e-6,
  );
  final GlassSpring _stretchY = GlassSpring(
    response: 0.314,
    dampingRatio: 1,
    tolerance: 1e-6,
  );

  // Lens position: an offset from where it belongs, springing to zero, on
  // one spring (0.405s response, damping 0.85) fitted to UIKit's lens
  // moving to a touched tab, sliding after a tap, and settling after a
  // flick (keeping its momentum). A touch starts it 24ms later.
  static const (double, double) _catchUp = (0.405, 0.85);
  static const double _catchUpDelay = 0.024;
  static const (double, double) _settle = _catchUp;

  // UIKit's lens trails a dragged finger: 8ms behind it, on a stiffer
  // spring (24 rad/s, damping 0.75; within 0.7pt of UIKit over five drags).
  // This lens does not trail, but its flex responds to the motion UIKit's
  // lens would make, so it deforms exactly as much for the same gesture.
  static const (double, double) _trail = (0.2618, 0.75);
  static const double _trailDelay = 0.008;
  final ListQueue<(double, double)> _anchorLog = ListQueue<(double, double)>();

  // Where the lens belonged at [t] (the anchor, as touches moved it); the
  // earliest one known if [t] is older.
  double _anchorAt(double t) {
    var earliest = _anchor;
    for (final (double time, double anchor) in _anchorLog.toList().reversed) {
      if (time <= t) {
        return anchor;
      }
      earliest = anchor;
    }
    return earliest;
  }

  void _logAnchor(double t) {
    _anchorLog.addLast((t, _anchor));
    while (_anchorLog.length > 2 && t - _anchorLog.elementAt(1).$1 > 0.1) {
      _anchorLog.removeFirst();
    }
  }

  final GlassSpring _shadow = GlassSpring(
    response: 0.5,
    dampingRatio: 0.75,
    tolerance: 0.02,
  );
  final GlassSpring _offset = GlassSpring(
    response: 0.5,
    dampingRatio: 0.75,
    tolerance: 0.02,
  );

  // Lift progress: the clear optics (UIKit's liftProgress, 631.65/50.27,
  // critically damped in 0.25s). A quick tap keeps the lens lifted for
  // [lensHangTime] after the finger leaves.
  static const double lensHangTime = 0.22;

  // UIKit starts the lift a frame after the touch; the platter at once.
  static const double _liftDelay = 0.015;
  static final (double, double) _liftSpring = (
    _r(631.654682),
    _z(631.654682, 50.265482),
  );
  final GlassSpring _lift = GlassSpring.physical(
    mass: 1,
    stiffness: 631.654682,
    damping: 50.265482,
    tolerance: 1e-4,
  );

  // Lens bounds grow by 8pt on each side as it lifts: with the lift while
  // the finger holds it, more slowly (the loupe spring) while it hangs
  // after a tap.
  static final (double, double) _hangGrowth = (_r(157.91367), 1.0);
  final GlassSpring _growth = GlassSpring.physical(
    mass: 1,
    stiffness: 631.654682,
    damping: 50.265482,
    tolerance: 1e-4,
  );

  // Flex: the lens is a soft body. Every change in its velocity on screen
  // (also as the swelling platter carries it), smoothed over 20ms as
  // UIKit's velocity integrator does, kicks one state m, which springs back
  // on UIKit's loupe flex spring (157.9/25.13, critically damped). m, taken
  // within ±0.46, sets the lens's scale and drift: x scales by 1 + 0.6m and
  // the lens drifts -14.8m points; y scales by 1 - m while m is small,
  // flattening at most about 40% and bulging at most 28%. The result eases
  // in on a slightly overdamped spring. Fitted to UIKit's flex state over
  // nine gestures.
  static const double _flexGain = 0.0173;
  static const double _flexSmoothing = 0.02;
  static const double _flexLimit = 0.46;
  static const double _flexScaleX = 0.6;
  static const double _flexFlattenKnee = 0.3;
  static const double _flexFlattenLimit = 0.4;
  static const double _flexBulgeLimit = 0.28;
  static const double _flexDrift = -14.8;
  final GlassSpring _flex = GlassSpring.physical(
    mass: 1,
    stiffness: 157.91367,
    damping: 25.132741,
    tolerance: 1e-5,
  );
  static const (double, double) _flexEase = (0.314, 1.15);
  double _smoothedVelocity = 0;
  final GlassSpring _flexX = GlassSpring(
    response: 0.314,
    dampingRatio: 1.15,
    value: 1,
    tolerance: 1e-5,
  );
  final GlassSpring _flexY = GlassSpring(
    response: 0.314,
    dampingRatio: 1.15,
    value: 1,
    tolerance: 1e-5,
  );
  final GlassSpring _flexShift = GlassSpring(
    response: 0.314,
    dampingRatio: 1.15,
    tolerance: 1e-3,
  );

  final GlassSpring _glow = GlassSpring.physical(
    mass: 1,
    stiffness: 631.654682,
    damping: 50.265482,
    tolerance: 1e-3,
  );

  List<GlassSpring> get _springs => <GlassSpring>[
    _scale,
    _stretchX,
    _stretchY,
    _offset,
    _shadow,
    _lift,
    _growth,
    _flex,
    _flexX,
    _flexY,
    _flexShift,
    _glow,
  ];

  // ------------------------------------------------------------------ touch

  Offset? _touch;
  Offset _touchStart = Offset.zero;
  double? _pressTime;
  double _hangUntil = double.negativeInfinity;

  // Touches wait here until the frame they happened in is stepped, so that
  // the springs respond from the moment of the touch, as UIKit's animations
  // do, and not from a frame boundary.
  final List<_TouchEvent> _pending = <_TouchEvent>[];

  // The finger as reported so far; the applied state follows within a
  // frame.
  Offset? _reported;

  double _now = 0;
  bool _started = false;

  // Whether the last frame found nothing moving: the next one starts from
  // an input that came in since, half a frame ago unless its time is known.
  bool _idle = true;
  static const double _firstStep = 1 / 120;

  /// Where the lens belongs: the finger (kept within the bar) while
  /// pressed, the selected tab's center otherwise. The lens sits at
  /// [_anchor] plus the offset spring.
  double _anchor = 0;
  final ListQueue<(double, double)> _history = ListQueue<(double, double)>();
  double _anchorVelocity = 0;

  bool get pressed => _touch != null;

  /// The finger, in bar coordinates, while pressed.
  Offset? get touch => _touch;

  /// Whether anything is still moving (or pressed).
  bool get isActive =>
      pressed ||
      _pending.isNotEmpty ||
      _now < _hangUntil ||
      _springs.any((GlassSpring s) => !s.isSettled);

  /// The lens's center along the bar, in platter coordinates (without its
  /// flex drift).
  double get lensX => _anchor + _offset.value;
  double get _lensVelocity => _anchorVelocity + _offset.velocity;

  /// A finger came down at [position], in bar coordinates. [time] is when,
  /// in seconds on the clock given to [tick]; without it the touch counts
  /// as half a frame before the next tick.
  void pointerDown(Offset position, {double? time}) {
    _reported = position;
    _pending.add(_TouchEvent(_Touch.down, time, position));
  }

  void pointerMove(Offset position, {double? time}) {
    if (_reported == null) {
      return;
    }
    _reported = position;
    _pending.add(_TouchEvent(_Touch.move, time, position));
  }

  /// Ends the touch and returns the tab it chose: the one nearest the lens,
  /// which is under the finger.
  int pointerUp({double? time}) {
    if (_reported == null) {
      return _selected;
    }
    _selected = nearestTab(_clampToBar(_reported!.dx));
    _reported = null;
    _pending.add(_TouchEvent(_Touch.up, time, null));
    return _selected;
  }

  void pointerCancel({double? time}) {
    if (_reported == null) {
      return;
    }
    _reported = null;
    _pending.add(_TouchEvent(_Touch.up, time, null));
  }

  void _apply(_TouchEvent event, double t) {
    switch (event.kind) {
      case _Touch.down:
        final Offset position = event.position!;
        _touch = position;
        _touchStart = position;
        _pressTime = t;
        _hangUntil = double.negativeInfinity;
        final double x = lensX, v = _lensVelocity;
        _anchor = _clampToBar(position.dx);
        _anchorVelocity = 0;
        _history.clear();
        _offset
          ..configure(_catchUp.$1, _catchUp.$2)
          ..value = x - _anchor
          ..velocity = v
          ..target = 0;
        _shadow.configure(_catchUp.$1, _catchUp.$2);
        _logAnchor(t);
      case _Touch.move:
        if (_touch == null) {
          return;
        }
        _touch = event.position;
        final double anchor = _clampToBar(event.position!.dx);
        if (anchor != _anchor) {
          _shadow.configure(_trail.$1, _trail.$2);
        }
        _anchor = anchor;
        _logAnchor(t);
      case _Touch.up:
        if (_touch == null) {
          return;
        }
        final double held = _pressTime == null ? 1 : t - _pressTime!;
        _hangUntil = held < lensHangTime ? t + lensHangTime : t;
        _release();
        _logAnchor(t);
    }
  }

  void _release() {
    _touch = null;
    final bool catchingUp = _offset.value.abs() > 20;
    final double x = lensX, v = _lensVelocity;
    _anchor = tabCenter(_selected);
    _anchorVelocity = 0;
    _history.clear();
    final (double r, double z) = catchingUp ? _catchUp : _settle;
    _offset
      ..configure(r, z)
      ..value = x - _anchor
      ..velocity = v
      ..target = 0;
    _shadow.configure(r, z);
  }

  /// The selection changed from outside (or a choice was not taken up).
  void select(int index) {
    if (index == _selected) {
      return;
    }
    _selected = index.clamp(0, _count - 1);
    if (_touch == null && _reported == null) {
      final double x = lensX, v = _lensVelocity;
      _anchor = tabCenter(_selected);
      _offset
        ..configure(_settle.$1, _settle.$2)
        ..value = x - _anchor
        ..velocity = v
        ..target = 0;
      _shadow.configure(_settle.$1, _settle.$2);
      _logAnchor(_now);
    }
  }

  // ------------------------------------------------------------------ frame

  /// Advances everything to [now] (in seconds; the same clock as touch
  /// times). Returns whether anything is still moving.
  bool tick(double now) {
    if (!_started) {
      _started = true;
      _now = now;
    }
    final double elapsed = math.max(now - _now, 0.0);
    double start =
        now - (_idle ? math.min(elapsed, _firstStep) : math.min(elapsed, 0.1));
    // Touch times: ignore any on another clock; a resting bar starts from
    // the earliest touch.
    double? timeOf(_TouchEvent e) {
      final double? t = e.time;
      return t == null || t < now - 0.1 || t > now + 0.05 ? null : t;
    }

    if (_idle) {
      for (final _TouchEvent e in _pending) {
        final double? t = timeOf(e);
        if (t != null) {
          start = math.min(start, math.max(t, now - 0.05));
        }
      }
    }
    var t = start;
    for (final _TouchEvent e in _pending) {
      final double te = (timeOf(e) ?? (start + now) / 2).clamp(t, now);
      _advance(t, te);
      _apply(e, te);
      t = te;
    }
    _pending.clear();
    _advance(t, now);
    _now = now;

    // The finger's speed along the bar, from where the anchor was over the
    // last 50ms of frames: it falls to zero as soon as the finger rests.
    if (_touch != null) {
      _history.addLast((now, _anchor));
      while (_history.length > 2 && now - _history.first.$1 > 0.05) {
        _history.removeFirst();
      }
      _anchorVelocity = _slope(_history);
    }

    _idle = !isActive;
    debugOnTick?.call(this, now);
    return !_idle;
  }

  // Steps every spring from [t0] to [t1] under the targets of the current
  // touch state, splitting where the lift and the catch-up start.
  void _advance(double t0, double t1) {
    if (t1 <= t0) {
      return;
    }
    final double? pressed = _pressTime;
    final List<double> splits = <double>[
      if (pressed != null && _touch != null) ...<double>[
        pressed + _liftDelay,
        pressed + _catchUpDelay,
      ],
    ]..removeWhere((double s) => s <= t0 || s >= t1);
    splits.sort();
    var a = t0;
    for (final double b in <double>[...splits, t1]) {
      _step(a, b - a);
      a = b;
    }
  }

  void _step(double t, double dt) {
    final bool down = _touch != null;
    final double since = _pressTime == null ? double.infinity : t - _pressTime!;

    // Platter.
    final (double sr, double sz) = down ? _swell : _unswell;
    _scale
      ..configure(sr, sz)
      ..target = down ? pressedScale : 1;
    double kx = 0, ky = 0;
    if (down) {
      final Offset p = _touch!;
      final Offset moved = p - _touchStart;
      final double outX = math.max(math.max(-p.dx, p.dx - _size.width), 0);
      final double outY = math.max(math.max(-p.dy, p.dy - _size.height), 0);
      final double sideX = moved.dx != 0
          ? moved.dx.sign
          : (p.dx < _size.width / 2 ? -1 : 1);
      final double sideY = moved.dy != 0
          ? moved.dy.sign
          : (p.dy < _size.height / 2 ? -1 : 1);
      kx =
          sideX *
          (_stretchPerPoint * moved.dx.abs() + _stretchPerOutsidePoint * outX);
      ky =
          sideY *
          (_stretchPerPoint * moved.dy.abs() + _stretchPerOutsidePoint * outY);
    }
    final (double kr, double kz) = down ? _stretchFollow : _unswell;
    _stretchX
      ..configure(kr, kz)
      ..target = kx;
    _stretchY
      ..configure(kr, kz)
      ..target = ky;

    // Lift and lens bounds: a frame after a touch, while held or hanging.
    final bool hanging = !down && t < _hangUntil;
    final bool lifted = (down && since >= _liftDelay) || hanging;
    _lift.target = lifted ? 1 : (down ? _lift.target : 0);
    final (double gr, double gz) = hanging ? _hangGrowth : _liftSpring;
    _growth
      ..configure(gr, gz)
      ..target = _lift.target;
    _glow.target = down ? 1 : 0;

    final double m = _flex.value.clamp(-_flexLimit, _flexLimit);
    _flex.target = 0;
    _flexX
      ..configure(_flexEase.$1, _flexEase.$2)
      ..target = 1 + _flexScaleX * m;
    _flexY
      ..configure(_flexEase.$1, _flexEase.$2)
      ..target = m >= 0
          ? 1 - _flatten(m)
          : 1 + _flexBulgeLimit * _tanh(-m / _flexBulgeLimit);
    _flexShift
      ..configure(_flexEase.$1, _flexEase.$2)
      ..target = _flexDrift * m;

    _shadow.target = _anchorAt(t - _trailDelay);

    // The lens waits a moment before moving to a touch. Stepping in slices
    // of at most 4ms lets the flex follow the lens's acceleration closely:
    // each change in its velocity on screen kicks the flex.
    final bool waiting = down && since < _catchUpDelay;
    final int slices = math.max(1, (dt / 0.004).ceil());
    final double h = dt / slices;
    for (var i = 0; i < slices; i++) {
      for (final GlassSpring s in _springs) {
        if (waiting && (s == _offset || s == _shadow)) {
          continue;
        }
        s.step(h);
      }
      _smoothedVelocity +=
          (_shadowScreenVelocity - _smoothedVelocity) *
          (1 - math.exp(-h / _flexSmoothing));
      final double v = _smoothedVelocity;
      _flex.velocity += _flexGain * (v - _kickVx);
      _kickVx = v;
    }
  }

  double _kickVx = 0;

  // How fast UIKit's trailing lens would move on screen: its own motion,
  // scaled and carried by the platter.
  double get _shadowScreenVelocity {
    final double kx = _stretchX.value.abs(), ky = _stretchY.value.abs();
    final double kxv = _stretchX.value.sign * _stretchX.velocity;
    final double kyv = _stretchY.value.sign * _stretchY.velocity;
    final double l = _scale.value, lv = _scale.velocity;
    final double sx = l * (1 + kx) / (1 + ky);
    final double sxv =
        lv * (1 + kx) / (1 + ky) +
        l * kxv / (1 + ky) -
        l * (1 + kx) * kyv / ((1 + ky) * (1 + ky));
    final double driftV = _driftPerStretch * _size.width * _stretchX.velocity;
    return driftV +
        _shadow.velocity * sx +
        (_shadow.value - _size.width / 2) * sxv;
  }

  // How much the lens flattens for m > 0: m itself up to a knee, then
  // easing toward a limit.
  static double _flatten(double m) {
    if (m <= _flexFlattenKnee) {
      return m;
    }
    const double room = _flexFlattenLimit - _flexFlattenKnee;
    return _flexFlattenKnee + room * _tanh((m - _flexFlattenKnee) / room);
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

  static double _slope(Iterable<(double, double)> samples) {
    final int n = samples.length;
    if (n < 2) {
      return 0;
    }
    var mt = 0.0, mx = 0.0;
    for (final (double t, double x) in samples) {
      mt += t;
      mx += x;
    }
    mt /= n;
    mx /= n;
    var num = 0.0, den = 0.0;
    for (final (double t, double x) in samples) {
      num += (t - mt) * (x - mx);
      den += (t - mt) * (t - mt);
    }
    return den == 0 ? 0 : num / den;
  }

  // ---------------------------------------------------------------- outputs

  /// The platter's swell alone (1 at rest, [pressedScale] pressed).
  double get platterScale => _scale.value;

  double get _kx => _stretchX.value.abs();
  double get _ky => _stretchY.value.abs();

  /// The platter's scale along x, with its stretch toward the finger.
  double get platterScaleX => _scale.value * (1 + _kx) / (1 + _ky);

  /// The platter's scale along y, with its stretch toward the finger.
  double get platterScaleY => _scale.value * (1 + _ky) / (1 + _kx);

  /// The platter's translation toward the finger.
  Offset get platterDrift => Offset(
    _driftPerStretch * _stretchX.value * _size.width,
    _driftPerStretch * _stretchY.value * _size.height,
  );

  /// Maps platter coordinates (the bar's layout) to where they are drawn.
  Offset toBar(Offset p) {
    final Offset d = platterDrift;
    return Offset(
      _size.width / 2 + d.dx + (p.dx - _size.width / 2) * platterScaleX,
      _size.height / 2 + d.dy + (p.dy - _size.height / 2) * platterScaleY,
    );
  }

  /// The same mapping as [toBar], for painting the platter's content.
  Matrix4 get platterTransform {
    final Offset c = _size.center(Offset.zero);
    final Offset d = platterDrift;
    return Matrix4.identity()
      ..translateByDouble(c.dx + d.dx, c.dy + d.dy, 0, 1)
      ..scaleByDouble(platterScaleX, platterScaleY, 1, 1)
      ..translateByDouble(-c.dx, -c.dy, 0, 1);
  }

  /// The platter's outline, in bar coordinates.
  Rect get platterRect => Rect.fromCenter(
    center: toBar(_size.center(Offset.zero)),
    width: _size.width * platterScaleX,
    height: _size.height * platterScaleY,
  );

  /// 0 for the frosted resting pill, 1 for clear glass (UIKit's
  /// liftProgress).
  double get liftProgress => _lift.value.clamp(0.0, 1.0);

  /// Same as [liftProgress].
  double get clear => liftProgress;

  /// How far the lens's bounds have grown from the pill's (0 to 1).
  double get lift => _growth.value;

  /// The lens's flex scale (x, y) and drift, as drawn.
  Size get flexScale => Size(_flexX.value, _flexY.value);
  double get flexDrift => _flexShift.value;

  /// The soft-body state that drives the flex.
  double get flex => _flex.value;

  /// Log of the flex's x scale, for compatibility with earlier callers.
  double get stretch => math.log(math.max(_flexX.value, 1e-3));

  /// Fingertip glow, 0 to 1.
  double get glow => _glow.value.clamp(0.0, 1.0);

  /// The lens in platter coordinates: its bounds (the pill grown by the
  /// lift) with its flex scale, drifted by the flex.
  Rect get lensInPlatter {
    final double grow = 2 * liftOutset * math.max(_growth.value, -0.25);
    return Rect.fromCenter(
      center: Offset(lensX + _flexShift.value, _size.height / 2),
      width: (pillWidth + grow) * _flexX.value,
      height: (pillHeight + grow) * _flexY.value,
    );
  }

  /// The lens outline, in bar coordinates.
  Rect get lensRect {
    final Rect r = lensInPlatter;
    return Rect.fromCenter(
      center: toBar(r.center),
      width: r.width * platterScaleX,
      height: r.height * platterScaleY,
    );
  }

  @override
  String toString() =>
      'GlassTabBarPhysics(pressed: $pressed, lens: $lensRect, '
      'platter: $platterRect, lift: ${liftProgress.toStringAsFixed(3)}, '
      'flex: ${flex.toStringAsFixed(3)})';
}

enum _Touch { down, move, up }

class _TouchEvent {
  const _TouchEvent(this.kind, this.time, this.position);

  final _Touch kind;
  final double? time;
  final Offset? position;
}
