part of 'glass.dart';

/// Shows UIKit's popover (`UIPopoverPresentationController`, iOS 26) by the
/// widget [context] belongs to: a panel of glass beside it, its arrow
/// pointing at it, holding what [builder] makes. Completes with the value
/// the popover is popped with, or null when a tap outside dismisses it.
///
/// Placed as UIKit places its popovers (iPhone, iOS 26.5, kept as
/// popovers): above the widget if it fits there centered on it, else below,
/// else to its right, else to its left; failing that, on the first of those
/// sides it fits on, moved along to stay inside the screen (its arrow still
/// at the widget's middle); and if it fits nowhere, from the widget's
/// middle, on the side where the most of it shows. It keeps 10pt inside the
/// screen's sides and its safe area. It grows out of its arrow as it fades
/// in, overshooting a little; there is no dim, and a tap outside it
/// dismisses it.
///
/// [size] is the content's size (UIKit's `preferredContentSize`); by
/// default the content sizes itself, within the room there is.
///
/// Pass the context of the widget to point at: for a button, a context
/// inside it (a [Builder] around the button gives one).
Future<T?> showGlassPopover<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Size? size,
}) {
  final NavigatorState navigator = Navigator.of(context, rootNavigator: true);
  return navigator.push(
    _GlassPopoverRoute<T>(
      source: _popoverSource(context, navigator),
      size: size,
      builder: builder,
      themes: InheritedTheme.capture(from: context, to: navigator.context),
    ),
  );
}

// The box of the widget [context] belongs to, in [navigator]'s overlay's
// coordinates.
Rect _popoverSource(BuildContext context, NavigatorState navigator) {
  final RenderBox box = context.findRenderObject()! as RenderBox;
  final RenderObject? overlay = navigator.overlay?.context.findRenderObject();
  return MatrixUtils.transformRect(
    box.getTransformTo(overlay),
    Offset.zero & box.size,
  );
}

// UIKit's popover (iOS 26.5, iPhone 17 Pro Max, measured).
abstract final class _PopoverMetrics {
  static const double radius = 34;

  // The arrow: from the glass's edge out to its tip (shaders/glass.frag
  // draws it).
  static const double arrow = 13;

  // The popover keeps this far inside the screen's sides and its safe area.
  static const double margin = 10;

  // How near the arrow's middle comes to the glass's corners.
  static const double arrowEnd = 34 + 6;

  // An action sheet presented from a view.
  static const double actionSheetWidth = 240;

  // Its shadow (shaders/popover_shadow.frag) reaches this far past the
  // glass.
  static const double shadowReach = 150;
  static final ShaderProgram shadow = ShaderProgram('popover_shadow.frag');

  // Shown, it scales up from nothing and fades in on one spring, while its
  // middle comes from the arrow's tip to its place on a slightly bouncier
  // one that starts a moment later; dismissed, it goes back into the tip on
  // stiffer, nearly critical springs (scale, opacity and middle each its
  // own). Fitted to UIKit's frames (.research/popfit.py; RMS 0.001-0.008).
  static const (double, double) showScale = (18.0, 0.80);
  static const (double, double) showTravel = (17.0, 0.735);
  static const double travelDelay = 0.026;
  static const (double, double) hideScale = (17.6, 0.90);
  static const (double, double) hideOpacity = (16.8, 0.85);
  static const (double, double) hideTravel = (21.7, 0.95);
}

enum _PopoverSide { above, below, right, left }

typedef _PopoverPlace = ({Rect body, Offset tip, _PopoverSide side});

// Where UIKit puts a popover of [want] by [source], within [room] (the
// screen less its safe area and margins): see showGlassPopover.
_PopoverPlace _placePopover({
  required Rect source,
  required Size want,
  required Rect room,
}) {
  const double arrow = _PopoverMetrics.arrow;
  const double tolerance = 0.01;

  Rect space(_PopoverSide side, Rect from) => switch (side) {
    _PopoverSide.above => Rect.fromLTRB(
      room.left,
      room.top,
      room.right,
      from.top - arrow,
    ),
    _PopoverSide.below => Rect.fromLTRB(
      room.left,
      from.bottom + arrow,
      room.right,
      room.bottom,
    ),
    _PopoverSide.right => Rect.fromLTRB(
      from.right + arrow,
      room.top,
      room.right,
      room.bottom,
    ),
    _PopoverSide.left => Rect.fromLTRB(
      room.left,
      room.top,
      from.left - arrow,
      room.bottom,
    ),
  };
  bool vertical(_PopoverSide side) =>
      side == _PopoverSide.above || side == _PopoverSide.below;
  // On a side, the popover may narrow along the source's edge to the room
  // there is (UIKit's does); across it, it must fit.
  Size sized(_PopoverSide side, Rect s) => vertical(side)
      ? Size(math.min(want.width, s.width), want.height)
      : Size(want.width, math.min(want.height, s.height));
  bool fits(_PopoverSide side, Rect s) {
    final Size size = sized(side, s);
    return s.width >= size.width - tolerance &&
        s.height >= size.height - tolerance;
  }

  bool centered(_PopoverSide side, Rect s, Rect from) {
    final Size size = sized(side, s);
    return vertical(side)
        ? from.center.dx - size.width / 2 >= s.left - tolerance &&
              from.center.dx + size.width / 2 <= s.right + tolerance
        : from.center.dy - size.height / 2 >= s.top - tolerance &&
              from.center.dy + size.height / 2 <= s.bottom + tolerance;
  }

  _PopoverSide? side;
  Rect from = source;
  for (final _PopoverSide s in _PopoverSide.values) {
    if (fits(s, space(s, from)) && centered(s, space(s, from), from)) {
      side = s;
      break;
    }
  }
  side ??= _PopoverSide.values
      .where((_PopoverSide s) => fits(s, space(s, from)))
      .firstOrNull;
  if (side == null) {
    // Nowhere: from the source's middle, where the most of it shows.
    from = Rect.fromCenter(center: source.center, width: 0, height: 0);
    double best = -1;
    for (final _PopoverSide s in _PopoverSide.values) {
      final Rect sp = space(s, from);
      final double area =
          math.max(0.0, math.min(want.width, sp.width)) *
          math.max(0.0, math.min(want.height, sp.height));
      if (area > best + tolerance) {
        best = area;
        side = s;
      }
    }
  }
  final _PopoverSide chosen = side!;
  final Rect sp = space(chosen, from);
  final double w = math.max(0.0, math.min(want.width, sp.width));
  final double h = math.max(0.0, math.min(want.height, sp.height));
  double along(double middle, double start, double end, double length) =>
      end - start <= length
      ? start
      : (middle - length / 2).clamp(start, end - length);
  // UIKit keeps the popover's origin on whole points (its arrow follows).
  final Offset origin = switch (chosen) {
    _PopoverSide.above => Offset(
      along(from.center.dx, sp.left, sp.right, w),
      sp.bottom - h,
    ),
    _PopoverSide.below => Offset(
      along(from.center.dx, sp.left, sp.right, w),
      sp.top,
    ),
    _PopoverSide.right => Offset(
      sp.left,
      along(from.center.dy, sp.top, sp.bottom, h),
    ),
    _PopoverSide.left => Offset(
      sp.right - w,
      along(from.center.dy, sp.top, sp.bottom, h),
    ),
  };
  final Rect body =
      Offset(origin.dx.roundToDouble(), origin.dy.roundToDouble()) & Size(w, h);
  double aim(double middle, double start, double end) {
    const double inset = _PopoverMetrics.arrowEnd;
    return end - start <= 2 * inset
        ? (start + end) / 2
        : middle.clamp(start + inset, end - inset);
  }

  final Offset tip = switch (chosen) {
    _PopoverSide.above => Offset(
      aim(from.center.dx, body.left, body.right),
      body.bottom + arrow,
    ),
    _PopoverSide.below => Offset(
      aim(from.center.dx, body.left, body.right),
      body.top - arrow,
    ),
    _PopoverSide.right => Offset(
      body.left - arrow,
      aim(from.center.dy, body.top, body.bottom),
    ),
    _PopoverSide.left => Offset(
      body.right + arrow,
      aim(from.center.dy, body.top, body.bottom),
    ),
  };
  return (body: body, tip: tip, side: chosen);
}

// The popover's motion (see _PopoverMetrics): its scale, its opacity, and
// how far its middle has come from the arrow's tip to its place.
class _PopoverMotion {
  static GlassSpring _spring((double, double) omegaZeta) => GlassSpring(
    response: 2 * math.pi / omegaZeta.$1,
    dampingRatio: omegaZeta.$2,
  );

  final GlassSpring scale = _spring(_PopoverMetrics.showScale);
  final GlassSpring opacity = _spring(_PopoverMetrics.showScale);
  final GlassSpring travel = _spring(_PopoverMetrics.showTravel);
  double _delay = 0;

  static void _configure(GlassSpring spring, (double, double) omegaZeta) =>
      spring.configure(2 * math.pi / omegaZeta.$1, omegaZeta.$2);

  void show() {
    scale.target = 1;
    opacity.target = 1;
    _delay = _PopoverMetrics.travelDelay;
  }

  void hide() {
    _configure(scale, _PopoverMetrics.hideScale);
    _configure(opacity, _PopoverMetrics.hideOpacity);
    _configure(travel, _PopoverMetrics.hideTravel);
    scale.target = 0;
    opacity.target = 0;
    travel.target = 0;
    _delay = 0;
  }

  void step(double dt) {
    scale.step(dt);
    opacity.step(dt);
    if (_delay > 0) {
      _delay -= dt;
      if (_delay <= 0) {
        travel.target = 1;
        travel.step(-_delay);
        _delay = 0;
      }
    } else {
      travel.step(dt);
    }
  }

  bool get isSettled =>
      _delay <= 0 && scale.isSettled && opacity.isSettled && travel.isSettled;

  void settle() {
    scale.snap(scale.target);
    opacity.snap(opacity.target);
    travel.snap(travel.target);
  }

  double get shown => opacity.value.clamp(0.0, 1.0);
}

// Lays a popover's glass out by its source (the child: the glass, sized to
// its content or [size]) and moves it by its motion; gives the glass its
// arrow.
class _PopoverLayout extends SingleChildRenderObjectWidget {
  const _PopoverLayout({
    required this.source,
    required this.size,
    required this.insets,
    required this.arrow,
    required this.scale,
    required this.travel,
    required this.shadow,
    required this.devicePixelRatio,
    super.child,
  });

  final Rect source;
  final Size? size;
  final EdgeInsets insets;
  final ValueNotifier<_GlassArrow?> arrow;
  final double scale;
  final double travel;

  // How much of its shadow shows (its opacity), and the screen's pixels.
  final double shadow;
  final double devicePixelRatio;

  @override
  _RenderPopoverLayout createRenderObject(BuildContext context) =>
      _RenderPopoverLayout(
        source: source,
        size: size,
        insets: insets,
        arrow: arrow,
        scale: scale,
        travel: travel,
        shadow: shadow,
        devicePixelRatio: devicePixelRatio,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderPopoverLayout renderObject,
  ) {
    renderObject
      ..source = source
      ..wanted = size
      ..insets = insets
      ..arrow = arrow
      ..scale = scale
      ..travel = travel
      ..shadow = shadow
      ..devicePixelRatio = devicePixelRatio;
  }
}

class _RenderPopoverLayout extends RenderShiftedBox {
  _RenderPopoverLayout({
    required this._source,
    required Size? size,
    required this._insets,
    required this.arrow,
    required this._scale,
    required this._travel,
    required this._shadow,
    required this._devicePixelRatio,
  }) : _wanted = size,
       super(null);

  ValueNotifier<_GlassArrow?> arrow;

  Rect get source => _source;
  Rect _source;
  set source(Rect value) {
    if (value != _source) {
      _source = value;
      markNeedsLayout();
    }
  }

  Size? get wanted => _wanted;
  Size? _wanted;
  set wanted(Size? value) {
    if (value != _wanted) {
      _wanted = value;
      markNeedsLayout();
    }
  }

  EdgeInsets get insets => _insets;
  EdgeInsets _insets;
  set insets(EdgeInsets value) {
    if (value != _insets) {
      _insets = value;
      markNeedsLayout();
    }
  }

  double get scale => _scale;
  double _scale;
  set scale(double value) {
    if (value != _scale) {
      _scale = value;
      markNeedsPaint();
    }
  }

  double get travel => _travel;
  double _travel;
  set travel(double value) {
    if (value != _travel) {
      _travel = value;
      markNeedsPaint();
    }
  }

  double get shadow => _shadow;
  double _shadow;
  set shadow(double value) {
    if (value != _shadow) {
      _shadow = value;
      markNeedsPaint();
    }
  }

  double get devicePixelRatio => _devicePixelRatio;
  double _devicePixelRatio;
  set devicePixelRatio(double value) {
    if (value != _devicePixelRatio) {
      _devicePixelRatio = value;
      markNeedsPaint();
    }
  }

  _PopoverPlace? _place;

  final LayerHandle<ClipRectLayer> _shadowClip = LayerHandle<ClipRectLayer>();
  final LayerHandle<BackdropFilterLayer> _shadowLayer =
      LayerHandle<BackdropFilterLayer>();
  ui.FragmentShader? _shadowShader;

  @override
  void dispose() {
    _shadowClip.layer = null;
    _shadowLayer.layer = null;
    _shadowShader?.dispose();
    super.dispose();
  }

  @override
  void performLayout() {
    size = constraints.biggest;
    final RenderBox? child = this.child;
    if (child == null) {
      _place = null;
      return;
    }
    const double margin = _PopoverMetrics.margin;
    final Rect room = Rect.fromLTRB(
      _insets.left + margin,
      _insets.top + margin,
      size.width - _insets.right - margin,
      size.height - _insets.bottom - margin,
    );
    Size want;
    if (_wanted != null) {
      want = _wanted!;
    } else {
      child.layout(
        BoxConstraints.loose(
          Size(math.max(0.0, room.width), math.max(0.0, room.height)),
        ),
        parentUsesSize: true,
      );
      want = child.size;
    }
    final _PopoverPlace place = _placePopover(
      source: _source,
      want: want,
      room: room,
    );
    if (_wanted != null || place.body.size != child.size) {
      child.layout(BoxConstraints.tight(place.body.size), parentUsesSize: true);
    }
    (child.parentData! as BoxParentData).offset = place.body.topLeft;
    _place = place;
    final _GlassArrow glassArrow = (
      tip: place.tip - place.body.topLeft,
      direction: switch (place.side) {
        _PopoverSide.above => const Offset(0, 1),
        _PopoverSide.below => const Offset(0, -1),
        _PopoverSide.right => const Offset(-1, 0),
        _PopoverSide.left => const Offset(1, 0),
      },
    );
    if (arrow.value != glassArrow) {
      arrow.value = glassArrow;
    }
  }

  // The motion, in this box's coordinates: the glass scaled about its
  // middle, which travels from the arrow's tip to its place.
  Matrix4 get _motion {
    final _PopoverPlace? place = _place;
    if (place == null || (_scale == 1 && _travel == 1)) {
      return Matrix4.identity();
    }
    final Offset c = place.body.center;
    final Offset at = place.tip + (c - place.tip) * _travel;
    return Matrix4.diagonal3Values(_scale, _scale, 1)
      ..setTranslationRaw(at.dx - _scale * c.dx, at.dy - _scale * c.dy, 0);
  }

  // The arrow's box (this box's coordinates, at rest): taps there are the
  // popover's.
  Rect? get _arrowBox {
    final _PopoverPlace? place = _place;
    if (place == null) {
      return null;
    }
    final Offset base = place.side == _PopoverSide.above
        ? place.tip - const Offset(0, _PopoverMetrics.arrow)
        : place.side == _PopoverSide.below
        ? place.tip + const Offset(0, _PopoverMetrics.arrow)
        : place.side == _PopoverSide.right
        ? place.tip + const Offset(_PopoverMetrics.arrow, 0)
        : place.tip - const Offset(_PopoverMetrics.arrow, 0);
    return Rect.fromPoints(place.tip, base).inflate(6);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final RenderBox? child = this.child;
    if (child == null || _scale <= 0) {
      return;
    }
    final Offset at = (child.parentData! as BoxParentData).offset;
    context.pushTransform(needsCompositing, offset, _motion, (
      PaintingContext context,
      Offset offset,
    ) {
      _paintShadow(context, offset, at & child.size);
      context.paintChild(child, offset + at);
    });
  }

  // UIKit's shadow under the glass ([body], this box's coordinates): it
  // changes what is under it, which the glass then reads.
  void _paintShadow(PaintingContext context, Offset offset, Rect body) {
    final ui.FragmentProgram? program = _PopoverMetrics.shadow.program;
    if (program == null) {
      _PopoverMetrics.shadow.load().then((_) {
        if (attached) {
          markNeedsPaint();
        }
      });
    }
    if (program == null ||
        !ui.ImageFilter.isShaderFilterSupported ||
        _shadow <= 0 ||
        body.isEmpty) {
      _shadowClip.layer = null;
      return;
    }
    final ui.FragmentShader shader = _shadowShader ??= program.fragmentShader();
    final Matrix4 toRoot = getTransformTo(null)..multiply(_motion);
    final Rect global = MatrixUtils.transformRect(toRoot, body);
    final double k = _devicePixelRatio * global.width / body.width;
    shader
      ..setFloat(2, global.center.dx * _devicePixelRatio)
      ..setFloat(3, global.center.dy * _devicePixelRatio)
      ..setFloat(4, global.width / 2 * _devicePixelRatio)
      ..setFloat(5, global.height / 2 * _devicePixelRatio)
      ..setFloat(6, k)
      ..setFloat(7, _shadow)
      ..setFloat(8, 0)
      ..setFloat(9, 0);
    _shadowClip.layer = context.pushClipRect(
      true,
      offset,
      body.inflate(_PopoverMetrics.shadowReach),
      (PaintingContext context, Offset offset) {
        final BackdropFilterLayer layer =
            (_shadowLayer.layer ??= BackdropFilterLayer())
              ..filter = ui.ImageFilter.shader(shader);
        context.pushLayer(
          layer,
          (PaintingContext context, Offset offset) {},
          offset,
        );
      },
      oldLayer: _shadowClip.layer,
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    transform.multiply(_motion);
    super.applyPaintTransform(child, transform);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final RenderBox? child = this.child;
    if (child == null || _scale <= 0) {
      return false;
    }
    final Offset at = (child.parentData! as BoxParentData).offset;
    final Matrix4 toChild = _motion
      ..multiply(Matrix4.translationValues(at.dx, at.dy, 0));
    return result.addWithPaintTransform(
      transform: toChild,
      position: position,
      hitTest: (BoxHitTestResult result, Offset position) =>
          child.hitTest(result, position: position),
    );
  }

  @override
  bool hitTestSelf(Offset position) =>
      _scale > 0 && (_arrowBox?.contains(position) ?? false);
}

class _GlassPopoverRoute<T> extends PopupRoute<T> {
  _GlassPopoverRoute({
    required this.source,
    required this.size,
    required this.builder,
    required this.themes,
  });

  final Rect source;
  final Size? size;
  final WidgetBuilder builder;
  final CapturedThemes themes;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => false;

  @override
  String? get barrierLabel => null;

  // The popover moves on its own springs; these only keep the route for
  // them.
  @override
  Duration get transitionDuration => const Duration(milliseconds: 300);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 300);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => themes.wrap(_GlassPopover<T>(route: this));
}

class _GlassPopover<T> extends StatefulWidget {
  const _GlassPopover({super.key, required this.route});

  final _GlassPopoverRoute<T> route;

  @override
  State<_GlassPopover<T>> createState() => _GlassPopoverState<T>();
}

class _GlassPopoverState<T> extends State<_GlassPopover<T>>
    with TickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  Duration? _last;
  final _PopoverMotion _motion = _PopoverMotion();
  // The glass's presence, as drawn (GlassPresence).
  late final AnimationController _presence = AnimationController(
    vsync: this,
    value: 0,
  );
  final ValueNotifier<_GlassArrow?> _arrow = ValueNotifier<_GlassArrow?>(null);
  bool _dismissing = false;

  @override
  void initState() {
    super.initState();
    widget.route.animation?.addStatusListener(_routeStatus);
    _motion.show();
    _ticker.start();
  }

  @override
  void dispose() {
    widget.route.animation?.removeStatusListener(_routeStatus);
    _ticker.dispose();
    _presence.dispose();
    _arrow.dispose();
    super.dispose();
  }

  void _routeStatus(AnimationStatus status) {
    if (status == AnimationStatus.reverse) {
      _dismiss(popped: true);
    }
  }

  void _tick(Duration elapsed) {
    final Duration? last = _last;
    _last = elapsed;
    if (last != null) {
      _motion.step((elapsed - last).inMicroseconds / 1e6);
    }
    if (_motion.isSettled) {
      _motion.settle();
      _ticker.stop();
    }
    _presence.value = _motion.shown;
    setState(() {});
  }

  void _dismiss({bool popped = false}) {
    if (_dismissing) {
      return;
    }
    _dismissing = true;
    _motion.hide();
    if (!_ticker.isActive) {
      _last = null;
      _ticker.start();
    }
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

  @override
  Widget build(BuildContext context) {
    final EdgeInsets padding = MediaQuery.paddingOf(context);
    final double keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final bool dark =
        MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    return Stack(
      children: <Widget>[
        // No dim: a tap outside the popover dismisses it.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _dismiss,
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            ignoring: _dismissing,
            child: _PopoverLayout(
              source: widget.route.source,
              size: widget.route.size,
              insets: padding.copyWith(
                bottom: math.max(padding.bottom, keyboard),
              ),
              arrow: _arrow,
              scale: math.max(0, _motion.scale.value),
              travel: _motion.travel.value,
              shadow: _motion.shown,
              devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
              child: Semantics(
                scopesRoute: true,
                namesRoute: true,
                explicitChildNodes: true,
                child: GlassPresence(
                  amount: _presence,
                  child: Glass._popover(
                    _arrow,
                    radius: _PopoverMetrics.radius,
                    child: Opacity(
                      opacity: _motion.shown,
                      child: DefaultTextStyle.merge(
                        style: TextStyle(
                          color: dark
                              ? const Color(0xFFFFFFFF)
                              : const Color(0xFF000000),
                          decoration: TextDecoration.none,
                        ),
                        child: Builder(builder: widget.route.builder),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
