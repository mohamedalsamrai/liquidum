part of 'glass.dart';

/// How tall a sheet from [showGlassSheet] stands: UIKit's sheet detents
/// (`UISheetPresentationController.Detent`).
@immutable
class GlassSheetDetent {
  /// A sheet [height] points tall above the bottom safe area, as UIKit's
  /// custom detents (no taller than [large]).
  const GlassSheetDetent.height(double this.height) : _fraction = null;

  const GlassSheetDetent._(this._fraction) : height = null;

  /// UIKit's medium detent: 0.56 of [large] (481.6pt on a 6.9" iPhone).
  static const GlassSheetDetent medium = GlassSheetDetent._(0.56);

  /// UIKit's large detent: the whole screen below the status bar.
  static const GlassSheetDetent large = GlassSheetDetent._(1);

  /// The height, for a detent made with [GlassSheetDetent.height].
  final double? height;
  final double? _fraction;

  double _resolve(double max) => math.min(height ?? max * _fraction!, max);

  @override
  bool operator ==(Object other) =>
      other is GlassSheetDetent &&
      other.height == height &&
      other._fraction == _fraction;

  @override
  int get hashCode => Object.hash(height, _fraction);
}

/// Shows UIKit's sheet (`UISheetPresentationController`, iOS 26) over the
/// screen, with [builder]'s content, and completes when it goes.
///
/// The sheet rises from the bottom over a dimmed screen to the smallest of
/// [detents]. Below the large detent it is a panel of glass held 8pt off
/// the screen's sides and bottom, its corners concentric with the
/// screen's; dragged toward the large detent it grows to the screen's
/// width and, past halfway, turns opaque. Drag it between its detents, or
/// down (or tap the dimmed screen) to dismiss it; `Navigator.pop` closes it
/// too. Measured on iOS 26.5: the geometry, the springs and the glass.
///
/// The content is laid out at the sheet's full width and current height
/// (the bottom safe area in its [MediaQuery] padding) and scaled with it.
Future<T?> showGlassSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  List<GlassSheetDetent> detents = const <GlassSheetDetent>[
    GlassSheetDetent.medium,
    GlassSheetDetent.large,
  ],
}) {
  assert(detents.isNotEmpty, 'A sheet needs a detent.');
  final NavigatorState navigator = Navigator.of(context, rootNavigator: true);
  return navigator.push(
    _GlassSheetRoute<T>(
      builder: builder,
      detents: detents,
      themes: InheritedTheme.capture(from: context, to: navigator.context),
    ),
  );
}

// UIKit's sheet (iOS 26.5, iPhone 17 Pro Max, measured).
abstract final class _SheetMetrics {
  // The screen's corners (a 6.9" iPhone's); the sheet's top corners.
  static const double screenRadius = 62;
  static const double topRadius = 38;
  // Its bottom corners, from screenRadius - 14 for a sheet of no height to
  // the screen's at the large detent.
  static const double bottomRadiusFall = 14;

  // Below the medium detent the sheet is scaled to leave this inset at its
  // sides and bottom; it grows to the full width at the large detent.
  static const double inset = 8;

  // The dim over the screen: black at 0.2, 0.48 in the dark.
  static const double dim = 0.2;
  static const double darkDim = 0.48;

  // Presenting and dismissing (a tap, Navigator.pop): critically damped.
  static const double showResponse = 2 * math.pi / 18.1;
  // A drag let go: to a detent, or down and away.
  static const double snapResponse = 2 * math.pi / 12.9;
  static const double snapDamping = 0.845;
  static const double flingResponse = 2 * math.pi / 15.4;
  // The opaque fill fades in and out on a spring of its own.
  static const double fillResponse = 2 * math.pi / 18.27;
  // How far a let-go drag's speed carries (UIScrollView's normal
  // deceleration's projection, seconds).
  static const double projection = 0.499;
  // Dragged past the largest detent.
  static const double stretch = 60;

  static const Color lightFill = Color(0xFFFFFFFF);
  static const Color darkFill = Color(0xFF1C1C1E);
}

class _GlassSheetRoute<T> extends PopupRoute<T> {
  _GlassSheetRoute({
    required this.builder,
    required this.detents,
    required this.themes,
  });

  final WidgetBuilder builder;
  final List<GlassSheetDetent> detents;
  final CapturedThemes themes;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => false;

  @override
  String? get barrierLabel => null;

  // The sheet moves on its own springs; these only keep the route for them.
  @override
  Duration get transitionDuration => const Duration(milliseconds: 500);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 600);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => themes.wrap(_GlassSheet(route: this));
}

class _GlassSheet extends StatefulWidget {
  const _GlassSheet({required this.route});

  final _GlassSheetRoute<dynamic> route;

  @override
  State<_GlassSheet> createState() => _GlassSheetState();
}

class _GlassSheetState extends State<_GlassSheet>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  Duration? _last;

  // How much of the sheet stands above the screen's bottom (points).
  final GlassSpring _extent = GlassSpring(
    response: _SheetMetrics.showResponse,
    dampingRatio: 1,
    tolerance: 0.01,
  );
  final GlassSpring _fill = GlassSpring(
    response: _SheetMetrics.fillResponse,
    dampingRatio: 1,
    tolerance: 1e-3,
  );
  // A finger on the sheet swells it, as UIKit's interactive glass.
  final GlassSpring _press = GlassSpring.physical(
    mass: 1,
    stiffness: 541.5,
    damping: 29.1,
    tolerance: 1e-3,
  );

  bool _started = false;
  bool _presenting = true;
  bool _dismissing = false;
  double _frozenHeight = 0;
  double? _dragRaw;
  _SheetGeometry? _geometry;

  @override
  void initState() {
    super.initState();
    widget.route.animation?.addStatusListener(_routeStatus);
  }

  @override
  void dispose() {
    widget.route.animation?.removeStatusListener(_routeStatus);
    _ticker.dispose();
    super.dispose();
  }

  void _routeStatus(AnimationStatus status) {
    if (status == AnimationStatus.reverse) {
      _dismiss(popped: true);
    }
  }

  void _wake() {
    if (!_ticker.isActive) {
      _last = null;
      _ticker.start();
    }
  }

  void _tick(Duration elapsed) {
    final Duration? last = _last;
    _last = elapsed;
    if (last != null) {
      final double dt = (elapsed - last).inMicroseconds / 1e6;
      if (_dragRaw == null) {
        _extent.step(dt);
      }
      _fill.step(dt);
      _press.step(dt);
    }
    final _SheetGeometry? g = _geometry;
    if (g != null && !_dismissing) {
      _fill.target = _height(g) > g.opaqueAbove ? 1 : 0;
    }
    if (_extent.isSettled && _dragRaw == null) {
      _extent.snap(_extent.target);
      _presenting = false;
    }
    if (_extent.isSettled &&
        _fill.isSettled &&
        _press.isSettled &&
        _dragRaw == null) {
      _fill.snap(_fill.target);
      _press.snap(_press.target);
      _ticker.stop();
    }
    setState(() {});
  }

  // The sheet's height before its scale: its detent's (and the bottom
  // safe area), taller while dragged above its lowest.
  double _height(_SheetGeometry g) =>
      _dismissing ? _frozenHeight : math.max(_extent.value, g.extents.first);

  void _dismiss({bool popped = false, double velocity = 0}) {
    if (_dismissing) {
      return;
    }
    final _SheetGeometry? g = _geometry;
    _frozenHeight = g == null ? _extent.value : _height(g);
    _dismissing = true;
    _presenting = false;
    _dragRaw = null;
    if (velocity == 0) {
      _extent.configure(_SheetMetrics.showResponse, 1);
    } else {
      _extent
        ..configure(_SheetMetrics.flingResponse, 1)
        ..velocity = velocity;
    }
    _extent.target = 0;
    _press.target = 0;
    _wake();
    if (!popped) {
      final NavigatorState? navigator = widget.route.navigator;
      if (navigator != null && widget.route.isActive) {
        if (widget.route.isCurrent) {
          navigator.pop();
        } else {
          navigator.removeRoute(widget.route);
        }
      }
    }
  }

  void _dragStart(DragStartDetails details) {
    if (_dismissing) {
      return;
    }
    _presenting = false;
    _dragRaw = _extent.value;
    _extent.velocity = 0;
    _wake();
  }

  void _dragUpdate(DragUpdateDetails details) {
    final _SheetGeometry? g = _geometry;
    final double? raw = _dragRaw;
    if (_dismissing || g == null || raw == null) {
      return;
    }
    final double next = math.max(0.0, raw - details.delta.dy);
    _dragRaw = next;
    final double top = g.extents.last;
    // Past the largest detent the sheet stretches less and less.
    _extent.value = next <= top
        ? next
        : top +
              (1 - 1 / ((next - top) * 0.55 / _SheetMetrics.stretch + 1)) *
                  _SheetMetrics.stretch;
    _extent.target = _extent.value;
    _wake();
  }

  void _dragEnd(DragEndDetails details) {
    final _SheetGeometry? g = _geometry;
    if (_dismissing || g == null || _dragRaw == null) {
      return;
    }
    _dragRaw = null;
    final double velocity = -details.velocity.pixelsPerSecond.dy;
    final double projected =
        _extent.value + velocity * _SheetMetrics.projection;
    double target = 0;
    for (final double e in g.extents) {
      if ((e - projected).abs() < (target - projected).abs()) {
        target = e;
      }
    }
    if (target == 0) {
      _dismiss(velocity: velocity);
      return;
    }
    _extent
      ..configure(_SheetMetrics.snapResponse, _SheetMetrics.snapDamping)
      ..velocity = velocity
      ..target = target;
    _wake();
  }

  void _pressDown(PointerDownEvent event) {
    if (_dismissing) {
      return;
    }
    _press
      ..configure(2 * math.pi / math.sqrt(541.5), 29.1 / (2 * math.sqrt(541.5)))
      ..target = 1;
    _wake();
  }

  void _pressUp(PointerEvent event) {
    _press
      ..configure(2 * math.pi / math.sqrt(246.7), 11.8 / (2 * math.sqrt(246.7)))
      ..target = 0;
    _wake();
  }

  @override
  Widget build(BuildContext context) {
    final Size screen = MediaQuery.sizeOf(context);
    final EdgeInsets padding = MediaQuery.paddingOf(context);
    final _SheetGeometry g = _geometry = _SheetGeometry(
      screen,
      padding,
      MediaQuery.devicePixelRatioOf(context),
      widget.route.detents,
    );
    if (!_started) {
      _started = true;
      _extent
        ..snap(0)
        ..target = g.extents.first;
      _fill.snap(g.extents.first > g.opaqueAbove ? 1 : 0);
      _wake();
    }
    final bool dark =
        MediaQuery.platformBrightnessOf(context) == Brightness.dark;

    final double e = _extent.value;
    final double height = _height(g);
    final double scale = g.scaleAt(height);
    final double inset = (1 - scale) * screen.width / 2;
    // Presenting or dismissing, how far in it is; dragged, how far it is
    // from its lowest detent to gone.
    final double shown = (_presenting || _dismissing)
        ? (height <= 0 ? 0.0 : (e / height).clamp(0.0, 1.0))
        : (e / g.extents.first).clamp(0.0, 1.0);
    // UIKit's sheet comes in from the left of its place by its inset.
    final double drift = _presenting
        ? -inset * (1 - (e / height).clamp(0.0, 1.0))
        : 0.0;
    final Rect rest = Rect.fromLTRB(
      inset + drift,
      screen.height - inset - scale * height,
      screen.width - inset + drift,
      screen.height - inset,
    );
    final Rect place = rest.shift(Offset(0, math.max(0.0, height - e)));
    final double swell = 1 + _press.value * 4 / rest.width;
    final Rect visual = Rect.fromCenter(
      center: place.center,
      width: place.width * swell,
      height: place.height * swell,
    );
    final double k = visual.width / screen.width;
    final double bottomRadius = math.min(
      _SheetMetrics.screenRadius,
      _SheetMetrics.screenRadius -
          _SheetMetrics.bottomRadiusFall * (1 - height / g.large),
    );
    final BorderRadius corners = BorderRadius.vertical(
      top: const Radius.circular(_SheetMetrics.topRadius),
      bottom: Radius.circular(bottomRadius),
    );
    final double fill = _fill.value.clamp(0.0, 1.0);

    final Widget sheet = SizedBox(
      width: screen.width,
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          if (fill < 1)
            Glass._sheet(
              radius: _SheetMetrics.topRadius,
              bottomRadius: bottomRadius,
              child: const SizedBox.expand(),
            ),
          if (fill > 0)
            Opacity(
              opacity: fill,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: dark
                      ? _SheetMetrics.darkFill
                      : _SheetMetrics.lightFill,
                  borderRadius: corners,
                ),
              ),
            ),
          ClipRRect(
            borderRadius: corners,
            child: MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(padding: EdgeInsets.only(bottom: padding.bottom)),
              child: Builder(builder: widget.route.builder),
            ),
          ),
        ],
      ),
    );

    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _dismiss,
            child: ColoredBox(
              color: Color.fromRGBO(
                0,
                0,
                0,
                (dark ? _SheetMetrics.darkDim : _SheetMetrics.dim) * shown,
              ),
            ),
          ),
        ),
        Positioned(
          left: visual.left,
          top: visual.top,
          width: screen.width,
          height: height,
          child: Transform.scale(
            scale: k,
            alignment: Alignment.topLeft,
            child: Semantics(
              scopesRoute: true,
              explicitChildNodes: true,
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: _pressDown,
                onPointerUp: _pressUp,
                onPointerCancel: _pressUp,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragStart: _dragStart,
                  onVerticalDragUpdate: _dragUpdate,
                  onVerticalDragEnd: _dragEnd,
                  onVerticalDragCancel: () => _dragEnd(DragEndDetails()),
                  child: sheet,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A sheet's detents on a screen: their extents (the sheet's height above
/// the screen's bottom, its bottom safe area included), smallest first.
class _SheetGeometry {
  _SheetGeometry(
    Size screen,
    EdgeInsets padding,
    this.pixelRatio,
    List<GlassSheetDetent> list,
  ) : width = screen.width,
      bottom = padding.bottom,
      max = math.max(0.0, screen.height - padding.top - padding.bottom) {
    extents = <double>{
      for (final GlassSheetDetent d in list) _extent(d),
    }.toList()..sort();
  }

  final double width;
  final double bottom;
  final double max;
  final double pixelRatio;
  late final List<double> extents;

  // UIKit rounds a detent to the screen's pixels (its medium detent on a
  // 6.9" iPhone, 481.6pt, stands 481.67pt).
  double _extent(GlassSheetDetent d) =>
      (d._resolve(max) * pixelRatio).round() / pixelRatio + bottom;

  double get medium => _extent(GlassSheetDetent.medium);
  double get large => max + bottom;

  /// Past halfway from the medium detent to the large one, UIKit's sheet
  /// turns opaque.
  double get opaqueAbove => (medium + large) / 2;

  /// UIKit's scale: the inset at and below the medium detent, none at the
  /// large one, in proportion between.
  double scaleAt(double height) {
    final double low = 1 - 2 * _SheetMetrics.inset / width;
    final double t = large <= medium
        ? 1.0
        : ((height - medium) / (large - medium)).clamp(0.0, 1.0);
    return low + (1 - low) * t;
  }
}
