part of 'page.dart';

/// A platter of a navigation bar as laid out: the back button or a group of
/// items, and its box in the bar.
class _Lane {
  const _Lane({required this.rect, required this.items, this.back = false});

  final Rect rect;
  final List<GlassBarItem> items;
  final bool back;

  /// The same platter (UIKit leaves it as it is between the two pages).
  bool sameAs(_Lane other) {
    if (back != other.back || items.length != other.items.length) {
      return false;
    }
    for (var i = 0; i < items.length; i++) {
      final GlassBarItem a = items[i];
      final GlassBarItem b = other.items[i];
      if (a.icon != b.icon ||
          a.label != b.label ||
          a.prominent != b.prominent ||
          a.tint != b.tint) {
        return false;
      }
    }
    return true;
  }
}

/// UIKit's navigation bar between two pages (iOS 26.5, fitted to its layer
/// frames pushing and popping). The bar stays; the pages slide under it;
/// its platters pair from the bar's ends inward.
abstract final class _BarMotion {
  // A platter whose items change: its width on omega 15.1, damping ratio
  // 0.75, from 0.075s; its items crossfade on the same omega, critically
  // damped; it swells and settles as 1 + 0.5 e^(-zeta w t) sin(w_d t),
  // omega 12.7, damping ratio 0.53, from 0.035s (peaking at 1.23).
  static const double widthResponse = 2 * math.pi / 15.1;
  static const double widthDamping = 0.75;
  static const double delay = 0.075;
  static const double swellResponse = 2 * math.pi / 12.7;
  static const double swellDamping = 0.53;
  static const double swellKick = 0.5;
  static const double swellDelay = 0.035;

  // A platter only on the page going melts into its neighbor (toward the
  // bar's end): to a circle half its height across at the neighbor's
  // center, on the width's spring, its items fading at once (omega 30).
  // One only on the page coming grows out of its neighbor's center, from
  // a circle 0.2 of its height across, from 0.21s, omega 20, damping 0.7.
  static const double absorbed = 0.5;
  static const double vanishResponse = 2 * math.pi / 30;
  static const double emergeFrom = 0.2;
  static const double emergeResponse = 2 * math.pi / 20;
  static const double emergeDamping = 0.7;
  static const double emergeDelay = 0.21;

  // The back button appearing: its glass materializes (omega 13.5,
  // critically damped, from 0.044s), its chevron fades in (12.4, 0.91,
  // from 0.1s). Going: 28.8 and 0.93 from 0.033s, and 25.6.
  static const double backInResponse = 2 * math.pi / 13.5;
  static const double backInDelay = 0.044;
  static const double chevronInResponse = 2 * math.pi / 12.4;
  static const double chevronInDamping = 0.91;
  static const double chevronInDelay = 0.1;
  static const double backOutResponse = 2 * math.pi / 28.8;
  static const double backOutDamping = 0.93;
  static const double backOutDelay = 0.033;
  static const double chevronOutResponse = 2 * math.pi / 25.6;

  // A toolbar on one page only stays where it is and materializes (omega
  // 25, critically damped, in about 0.2s) or goes as the back button
  // does; the same toolbar on both pages stays.
  static const double toolInResponse = 2 * math.pi / 25;

  // Titles ride with their pages: a page going under fades its own
  // (omega 30, gone in 0.1s); a page leaving, at once (omega 60).
  static const double titleUnderResponse = 2 * math.pi / 30;
  static const double titleLeavingResponse = 2 * math.pi / 60;
}

/// A spring that starts after [delay] seconds.
class _Delayed {
  _Delayed(this.spring, this.delay);

  final GlassSpring spring;
  double delay;

  double get value => spring.value;
  bool get isSettled => spring.isSettled;
}

/// A push or pop under way, run by the page on top (the one coming or
/// going): it draws both pages' platters morphing, fixed on the screen,
/// while the two pages hide their own.
class _BarTransition {
  _BarTransition({required this.below, required this.coming});

  /// The page under the one on top.
  final _GlassPageState below;

  /// Whether the page on top is coming (a push) or going (a pop).
  bool coming;

  /// Seconds since it started.
  double elapsed = 0;

  /// Whether a finger drives it (UIKit's interactive pop).
  bool gesture = false;

  /// The page on top's platters, as last laid out: the page under it
  /// finishes a pop with them once the page on top has gone.
  (List<_Lane>, List<_Lane>)? topLanes;

  final _Delayed width = _Delayed(
    GlassSpring(
      response: _BarMotion.widthResponse,
      dampingRatio: _BarMotion.widthDamping,
    ),
    _BarMotion.delay,
  );
  final _Delayed fade = _Delayed(
    GlassSpring(response: _BarMotion.widthResponse, dampingRatio: 1),
    _BarMotion.delay,
  );
  final _Delayed swell = _Delayed(
    GlassSpring(
      response: _BarMotion.swellResponse,
      dampingRatio: _BarMotion.swellDamping,
    ),
    _BarMotion.swellDelay,
  );
  final _Delayed vanish = _Delayed(
    GlassSpring(response: _BarMotion.vanishResponse, dampingRatio: 1),
    0,
  );
  final _Delayed emerge = _Delayed(
    GlassSpring(
      response: _BarMotion.emergeResponse,
      dampingRatio: _BarMotion.emergeDamping,
    ),
    _BarMotion.emergeDelay,
  );
  final _Delayed emergeFade = _Delayed(
    GlassSpring(response: _BarMotion.widthResponse, dampingRatio: 1),
    _BarMotion.emergeDelay,
  );

  // The back button's glass and chevron, where only one page has it.
  final _Delayed backGlass = _Delayed(
    GlassSpring(response: _BarMotion.backInResponse, dampingRatio: 1),
    _BarMotion.backInDelay,
  );
  final _Delayed chevron = _Delayed(
    GlassSpring(
      response: _BarMotion.chevronInResponse,
      dampingRatio: _BarMotion.chevronInDamping,
    ),
    _BarMotion.chevronInDelay,
  );
  final _Amount backAmount = _Amount();
  bool _kicked = false;

  /// The toolbars: the same on both pages (it stays), or the one of the
  /// page going going (out) and the other coming (in).
  bool toolSame = false;
  final _Delayed toolIn = _Delayed(
    GlassSpring(response: _BarMotion.toolInResponse, dampingRatio: 1),
    0,
  );
  final _Delayed toolOut = _Delayed(
    GlassSpring(
      response: _BarMotion.backOutResponse,
      dampingRatio: _BarMotion.backOutDamping,
      value: 1,
    ),
    0,
  );
  final _Amount toolInAmount = _Amount();
  final _Amount toolOutAmount = _Amount()..value = 1;

  List<_Delayed> get _all => <_Delayed>[
    width,
    fade,
    swell,
    vanish,
    emerge,
    emergeFade,
    backGlass,
    chevron,
    toolIn,
    toolOut,
  ];

  /// Starts toward the page that ends up showing (1), or back to the one
  /// it started from (0, a pop given up).
  void aim({required bool forward, required bool backIn}) {
    final double to = forward ? 1 : 0;
    toolIn.spring.target = to;
    toolOut.spring.target = 1 - to;
    for (final _Delayed d in <_Delayed>[
      width,
      fade,
      vanish,
      emerge,
      emergeFade,
    ]) {
      d.spring.target = to;
    }
    // The back button: in (materializing slowly) or out (quickly).
    final bool appearing = backIn == forward;
    backGlass.spring
      ..configure(
        appearing ? _BarMotion.backInResponse : _BarMotion.backOutResponse,
        appearing ? 1 : _BarMotion.backOutDamping,
      )
      ..target = backIn ? to : 1 - to;
    chevron.spring
      ..configure(
        appearing
            ? _BarMotion.chevronInResponse
            : _BarMotion.chevronOutResponse,
        appearing ? _BarMotion.chevronInDamping : 1,
      )
      ..target = backIn ? to : 1 - to;
    if (!appearing) {
      backGlass.delay = math.min(
        backGlass.delay,
        elapsed + _BarMotion.backOutDelay,
      );
      chevron.delay = math.min(chevron.delay, elapsed);
    }
  }

  /// Places every channel where a finger has taken the pop ([progress] 0,
  /// the page on top; 1, the page under it).
  void follow(double progress, {required bool backIn}) {
    // No swell after a finger has moved it.
    _kicked = true;
    for (final _Delayed d in <_Delayed>[
      width,
      fade,
      vanish,
      emerge,
      emergeFade,
    ]) {
      d.spring.snap(progress);
    }
    swell.spring.snap(0);
    backGlass.spring.snap(backIn ? progress : 1 - progress);
    chevron.spring.snap(backIn ? progress : 1 - progress);
    toolIn.spring.snap(progress);
    toolOut.spring.snap(1 - progress);
    _publish();
  }

  void _publish() {
    backAmount.value = backGlass.value;
    toolInAmount.value = toolIn.value;
    toolOutAmount.value = toolOut.value;
  }

  void step(double dt) {
    elapsed += dt;
    if (gesture) {
      return;
    }
    if (!_kicked && elapsed >= swell.delay) {
      // The swell: a kick from rest, as UIKit's platter bulging as it
      // changes and settling.
      _kicked = true;
      final double z = _BarMotion.swellDamping;
      final double w = 2 * math.pi / _BarMotion.swellResponse;
      swell.spring.velocity = _BarMotion.swellKick * w * math.sqrt(1 - z * z);
    }
    for (final _Delayed d in _all) {
      if (elapsed >= d.delay) {
        d.spring.step(dt);
      }
    }
    _publish();
  }

  bool get isSettled => _kicked && _all.every((_Delayed d) => d.isSettled);

  void dispose() {
    backAmount.dispose();
    toolInAmount.dispose();
    toolOutAmount.dispose();
  }
}

/// How strongly the bar items below show (a toolbar materializing between
/// two pages): their labels are drawn by the glass, so an opacity above
/// them would miss them.
class _ItemStrength extends InheritedWidget {
  const _ItemStrength({required this.value, required super.child});

  final double value;

  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ItemStrength>()?.value ?? 1;

  @override
  bool updateShouldNotify(_ItemStrength oldWidget) => value != oldWidget.value;
}

/// A value the springs set each frame, as an animation the glass listens to.
class _Amount extends Animation<double>
    with AnimationLocalListenersMixin, AnimationLocalStatusListenersMixin {
  double _value = 0;

  @override
  double get value => _value;
  set value(double v) {
    if (v != _value) {
      _value = v;
      notifyListeners();
    }
  }

  @override
  AnimationStatus get status => AnimationStatus.forward;

  @override
  void didRegisterListener() {}

  @override
  void didUnregisterListener() {}

  void dispose() => clearListeners();
}

/// Paints [child] where it would be if the page around it had not moved
/// (the route's slide): the bar stays while the pages slide under it, as
/// UIKit's. A move only (no layer), so its glass still shares its reads.
class _ScreenFixed extends SingleChildRenderObjectWidget {
  const _ScreenFixed({
    required this.page,
    required this.navigator,
    required this.frame,
    super.child,
  });

  /// The page that slides, and the navigator it slides in.
  final GlobalKey page;
  final BuildContext navigator;

  /// Changes every frame of the transition, to repaint.
  final int frame;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderScreenFixed(page, navigator);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderScreenFixed renderObject,
  ) {
    renderObject
      ..page = page
      ..navigator = navigator
      ..markNeedsPaint();
  }
}

class _RenderScreenFixed extends RenderProxyBox {
  _RenderScreenFixed(this.page, this.navigator);

  GlobalKey page;
  BuildContext navigator;
  double _dx = 0;

  double _measure() {
    final RenderObject? p = page.currentContext?.findRenderObject();
    final RenderObject? n = navigator.findRenderObject();
    if (p is! RenderBox || n is! RenderBox || !p.attached || !n.attached) {
      return 0;
    }
    return n.localToGlobal(Offset.zero).dx - p.localToGlobal(Offset.zero).dx;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    _dx = _measure();
    super.paint(context, offset + Offset(_dx, 0));
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    transform.translateByDouble(_dx, 0, 0, 1);
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) => false;
}

/// One platter between the two pages: from [from] (or nothing) to [to] (or
/// nothing), with the neighbor's box it melts into or grows out of.
class _LaneMorph extends StatelessWidget {
  const _LaneMorph({
    required this.from,
    required this.to,
    required this.neighbor,
    required this.motion,
    required this.content,
  });

  final _Lane? from;
  final _Lane? to;

  /// The neighbor's box now (toward the bar's end), if any.
  final Rect? neighbor;
  final _BarTransition motion;

  /// A lane's items, drawn on its glass this strongly (0 to 1): their
  /// labels are drawn by the glass, which an opacity above would miss.
  final Widget Function(_Lane lane, double strength) content;

  @override
  Widget build(BuildContext context) {
    final _Lane? a = from;
    final _Lane? b = to;
    // Unchanged: as it is.
    if (a != null && b != null && a.sameAs(b)) {
      return Positioned.fromRect(
        rect: Rect.lerp(a.rect, b.rect, motion.width.value)!,
        child: _glass(content(b, 1)),
      );
    }
    // The back button on one page only: it materializes or goes.
    final _Lane? only = a == null ? b : (b == null ? a : null);
    if (only != null && (only.back || neighbor == null)) {
      return Positioned.fromRect(
        rect: only.rect,
        child: GlassPresence(
          amount: motion.backAmount,
          child: _glass(content(only, motion.chevron.value.clamp(0.0, 1.0))),
        ),
      );
    }
    if (a != null && b != null) {
      // Changing: its width, a swell, its items crossfading.
      final double s = 1 + motion.swell.value;
      final Rect box = Rect.lerp(a.rect, b.rect, motion.width.value)!;
      final Rect swollen = Rect.fromCenter(
        center: box.center,
        width: box.width * s,
        height: box.height * s,
      );
      final double c = motion.fade.value.clamp(0.0, 1.0);
      return Positioned.fromRect(
        rect: swollen,
        child: _glass(
          ClipRRect(
            borderRadius: BorderRadius.circular(swollen.shortestSide / 2),
            child: OverflowBox(
              alignment: AlignmentDirectional.centerStart,
              maxWidth: double.infinity,
              child: Transform.scale(
                scale: s,
                alignment: AlignmentDirectional.centerStart,
                child: Stack(
                  alignment: AlignmentDirectional.centerStart,
                  children: <Widget>[
                    if (c < 1) content(a, 1 - c),
                    if (c > 0) content(b, c),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
    // On one page only, beside a neighbor: melting into it, or growing out
    // of it.
    final Rect center = neighbor!;
    if (a != null) {
      final double k = motion.width.value;
      final double d = a.rect.height * _BarMotion.absorbed;
      final Rect end = Rect.fromCenter(
        center: center.center,
        width: d,
        height: d,
      );
      final Rect box = Rect.lerp(a.rect, end, k)!;
      return Positioned.fromRect(
        rect: box,
        child: _glass(
          ClipRRect(
            borderRadius: BorderRadius.circular(box.shortestSide / 2),
            child: OverflowBox(
              maxWidth: double.infinity,
              child: content(a, (1 - motion.vanish.value).clamp(0.0, 1.0)),
            ),
          ),
        ),
      );
    }
    final double k = motion.emerge.value;
    final double d = b!.rect.height * _BarMotion.emergeFrom;
    final Rect start = Rect.fromCenter(
      center: center.center,
      width: d,
      height: d,
    );
    final Rect box = Rect.lerp(start, b.rect, k)!;
    return Positioned.fromRect(
      rect: box,
      child: _glass(
        ClipRRect(
          borderRadius: BorderRadius.circular(
            math.max(box.shortestSide, 0) / 2,
          ),
          child: OverflowBox(
            maxWidth: double.infinity,
            child: content(b, motion.emergeFade.value.clamp(0.0, 1.0)),
          ),
        ),
      ),
    );
  }

  static Widget _glass(Widget child) => Glass(child: child);
}
