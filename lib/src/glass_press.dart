part of 'glass.dart';

/// UIKit's interactive glass press (`_UIFlexInteraction`, iOS 26.5): what a
/// finger on glass does to it, by the glass's size.
///
/// The glass swells by [lift] points along its long side (uniformly), on
/// the liquid lens's lift spring, and springs back on release with a 28%
/// undershoot (the variant's scale spring). While pressed, a wash lightens
/// it and a glow 1.5 times its short side across (at most 160pt) brightens
/// it under the finger; the glow stops at the glass's edge, spreads to twice
/// its size at half its opacity once the finger leaves the glass, and to
/// four times as it fades after the touch. Dragging stretches the glass
/// toward the finger, keeping its area, and moves it a little that way.
///
/// UIKit's variants: glass up to 110pt long (any aspect) is "ultra small":
/// a 16pt swell, the glow at full strength, the full wash. Longer glass
/// goes from "small" to "large" with its short side, from 44 to 160pt: the
/// swell from 16 to 4pt, the glow from 0.3 to 0.2, the wash from full to
/// none (the tab bar's platter, 62pt, is small: 14.1pt, 0.2845, 0.845).
/// Fitted to UIKit's flex settings and its glass frame by frame.
class _GlassPress extends ChangeNotifier {
  _GlassPress() {
    _swell.snap(1);
    _stretch.snap(0);
  }

  // The variant's laws (UIKit's _UIFlexInteractionSettings): the swell's
  // points and the glow's opacity; the release's scale spring (stiffness,
  // damping, mass 1).
  static const double _ultraSmallLength = 115;
  static const (double, double) _smallSpring = (246.74, 11.78);
  static const (double, double) _largeSpring = (304.62, 20.94);

  /// How far the glass is from small (0) to large (1), by its short side.
  static double largeness(Size size) => size.longestSide <= _ultraSmallLength
      ? 0
      : ((size.shortestSide - 44) / 116).clamp(0.0, 1.0);

  static bool _ultraSmall(Size size) => size.longestSide <= _ultraSmallLength;

  /// The swell (points) for glass of [size].
  static double lift(Size size) => 16 - 12 * largeness(size);

  /// The glow's peak opacity for glass of [size].
  static double glowOpacity(Size size) =>
      _ultraSmall(size) ? 1 : 0.3 - 0.1 * largeness(size);

  /// The wash's opacity for glass of [size].
  static double washOpacity(Size size) =>
      _ultraSmall(size) ? 1 : 1 - largeness(size);

  // The swell rises on the liquid lens's lift spring (8% over at 0.17s).
  static const (double, double) _liftSpring = (541.54, 29.09);

  // The wash and glow: up within a tenth of a second, down over half a
  // second, critically damped; the glow's spread as the tab bar's.
  static const (double, double) _pressRise = (0.095, 1.0);
  static const (double, double) _pressFall = (0.499, 1.0);
  static const (double, double) _spreading = (0.53, 0.96);

  // The drag's stretch: up to UIKit's 10% (movement min 0.9, max 1.1),
  // growing with the square of the drag; and the drift toward the finger.
  // Approximate: fitted to four drags of 20 to 120pt on a 84 x 38pt button.
  static const double _stretchLimit = 0.1;
  static const double _stretchSquare = 20000;
  static const double _driftPerPoint = 0.025;
  static const double _driftLimit = 3;

  final GlassSpring _swell = GlassSpring.physical(
    mass: 1,
    stiffness: _liftSpring.$1,
    damping: _liftSpring.$2,
    tolerance: 1e-4,
  );
  final GlassSpring _press = GlassSpring(
    response: _pressRise.$1,
    dampingRatio: _pressRise.$2,
    tolerance: 1e-3,
  );
  final GlassSpring _spread = GlassSpring(
    response: _spreading.$1,
    dampingRatio: _spreading.$2,
    tolerance: 1e-3,
  );
  // The drag's stretch (its fraction) and drift (points), along [_along].
  final GlassSpring _stretch = GlassSpring(
    response: 0.4,
    dampingRatio: 0.375,
    tolerance: 1e-4,
  );
  final GlassSpring _driftX = GlassSpring(
    response: 0.4,
    dampingRatio: 0.375,
    tolerance: 1e-2,
  );
  final GlassSpring _driftY = GlassSpring(
    response: 0.4,
    dampingRatio: 0.375,
    tolerance: 1e-2,
  );
  Offset _along = const Offset(1, 0);

  Size _size = Size.zero;
  Offset? _touch;
  Offset _start = Offset.zero;
  Offset? _glow;
  double? _now;

  /// Whether a finger is on the glass.
  bool get pressed => _touch != null;

  bool get isActive =>
      pressed ||
      !_swell.isSettled ||
      !_press.isSettled ||
      !_spread.isSettled ||
      !_stretch.isSettled ||
      !_driftX.isSettled ||
      !_driftY.isSettled;

  /// The glass's size (points, unswollen).
  set size(Size value) => _size = value;

  /// A finger came down at [position] (glass coordinates, unswollen).
  void down(Offset position) {
    _touch = position;
    _start = position;
    _glow = position;
    _spread.snap(0);
    _swell
      ..configure(
        2 * math.pi / math.sqrt(_liftSpring.$1),
        _liftSpring.$2 / (2 * math.sqrt(_liftSpring.$1)),
      )
      ..target = _swollen;
    _press
      ..configure(_pressRise.$1, _pressRise.$2)
      ..target = 1;
    _aim();
  }

  void move(Offset position) {
    if (_touch == null) {
      return;
    }
    _touch = position;
    _aim();
  }

  /// The finger left (or the press was cancelled).
  void up() {
    if (_touch == null) {
      return;
    }
    _touch = null;
    final double t = largeness(_size);
    final double k = _smallSpring.$1 + (_largeSpring.$1 - _smallSpring.$1) * t;
    final double c = _smallSpring.$2 + (_largeSpring.$2 - _smallSpring.$2) * t;
    final double response = 2 * math.pi / math.sqrt(k);
    final double ratio = c / (2 * math.sqrt(k));
    _swell
      ..configure(response, ratio)
      ..target = 1;
    for (final GlassSpring s in <GlassSpring>[_stretch, _driftX, _driftY]) {
      s
        ..configure(response, ratio)
        ..target = 0;
    }
    _press
      ..configure(_pressFall.$1, _pressFall.$2)
      ..target = 0;
    _spread.target = 3;
  }

  double get _swollen => _size.longestSide <= 0
      ? 1
      : (_size.longestSide + lift(_size)) / _size.longestSide;

  // Where the glow, stretch and drift head while pressed.
  void _aim() {
    final Offset touch = _touch!;
    final Rect box = Offset.zero & _size;
    // The glow follows the finger within the glass and stops at its edge.
    _glow = Offset(
      touch.dx.clamp(box.left, box.right),
      touch.dy.clamp(box.top, box.bottom),
    );
    _spread.target = box.contains(touch) ? 0 : 1;
    final Offset moved = touch - _start;
    final double d = moved.distance;
    if (d > 1e-3) {
      _along = moved / d;
    }
    _stretch.target = _stretchLimit * _tanh(d * d / _stretchSquare);
    final double drift = math.min(_driftPerPoint * d, _driftLimit);
    _driftX.target = _along.dx * drift;
    _driftY.target = _along.dy * drift;
  }

  static double _tanh(double x) {
    final double e = math.exp(-2 * x);
    return (1 - e) / (1 + e);
  }

  /// Advances the springs to [now] (seconds); false once all is still.
  bool tick(double now) {
    final double dt = _now == null ? 0 : (now - _now!).clamp(0.0, 0.1);
    _now = now;
    final int slices = math.max(1, (dt / 0.004).ceil());
    for (var i = 0; i < slices; i++) {
      for (final GlassSpring s in <GlassSpring>[
        _swell,
        _press,
        _spread,
        _stretch,
        _driftX,
        _driftY,
      ]) {
        s.step(dt / slices);
      }
    }
    notifyListeners();
    if (!isActive) {
      _now = null;
      return false;
    }
    return true;
  }

  /// The glass's transform about its center, in its own coordinates: the
  /// swell, the stretch along the drag (area kept) and the drift.
  Matrix4 transform() {
    final double s = _swell.value;
    final double e = 1 + _stretch.value;
    final double a = _along.dx * _along.dx - _along.dy * _along.dy;
    final double sx = s * math.pow(e, a).toDouble();
    final double sy = s * math.pow(e, -a).toDouble();
    final Offset c = _size.center(Offset.zero);
    return Matrix4.identity()
      ..translateByDouble(c.dx + _driftX.value, c.dy + _driftY.value, 0, 1)
      ..scaleByDouble(sx, sy, 1, 1)
      ..translateByDouble(-c.dx, -c.dy, 0, 1);
  }

  bool get isIdentity =>
      _swell.value == 1 &&
      _stretch.value == 0 &&
      _driftX.value == 0 &&
      _driftY.value == 0;

  /// How pressed the glass is (0 to 1): its wash and glow follow.
  double get amount => _press.value.clamp(0.0, 1.0);

  /// The wash's opacity now.
  double get wash => washOpacity(_size) * amount;

  /// The glow's center (glass coordinates), null before any touch.
  Offset? get glowCenter => _glow;

  /// The glow's diameter and blur (gaussian sigma), in glass points.
  double get glowSize =>
      math.min(1.5 * _size.shortestSide, 160) * (1 + _spread.value);
  double get glowSigma => math.min(0.75 * _size.shortestSide, 80);

  /// The glow's opacity now.
  double get glowAlpha =>
      glowOpacity(_size) * amount * (1 - _spread.value.clamp(0.0, 1.0) / 2);
}

/// Paints its child through a [_GlassPress]'s transform: the glass swelling
/// and stretching under the finger, with what is on it.
class _PressTransform extends SingleChildRenderObjectWidget {
  const _PressTransform({required this.press, super.child});

  final _GlassPress? press;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderPressTransform(press);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderPressTransform).press = press;
  }
}

class _RenderPressTransform extends RenderProxyBox {
  _RenderPressTransform(this._press);

  _GlassPress? get press => _press;
  _GlassPress? _press;
  set press(_GlassPress? value) {
    if (value == _press) {
      return;
    }
    if (attached) {
      _press?.removeListener(markNeedsPaint);
      value?.addListener(markNeedsPaint);
    }
    _press = value;
    markNeedsPaint();
  }

  final LayerHandle<TransformLayer> _layer = LayerHandle<TransformLayer>();

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _press?.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _press?.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void dispose() {
    _layer.layer = null;
    super.dispose();
  }

  @override
  void performLayout() {
    super.performLayout();
    _press?.size = size;
  }

  Matrix4? get _transform {
    final _GlassPress? press = _press;
    return press == null || press.isIdentity ? null : press.transform();
  }

  // Touches land on the glass as it was (hit testing ignores the
  // transform): the press follows the finger wherever it goes.
  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final Matrix4? t = _transform;
    if (t != null) {
      transform.multiply(t);
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final Matrix4? t = _transform;
    if (child == null || t == null) {
      _layer.layer = null;
      super.paint(context, offset);
      return;
    }
    _layer.layer = context.pushTransform(
      needsCompositing,
      offset,
      t,
      super.paint,
      oldLayer: _layer.layer,
    );
  }
}
