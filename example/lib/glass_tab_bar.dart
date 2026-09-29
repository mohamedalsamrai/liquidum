import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/physics.dart';
import 'package:liquidum/liquidum.dart';

import 'sf_symbol.dart';

class GlassTabItem {
  const GlassTabItem({
    required this.icon,
    required this.label,
    required this.symbol,
  });

  final IconData icon;
  final String label;

  /// SF Symbol name, for the native bar this one is compared against.
  final String symbol;
}

/// An iOS 26 style tab bar: a glass capsule, a selection pill, the items, and
/// a clear glass lens that lifts out of the pill while the bar is pressed.
///
/// Press anywhere on the bar and slide to move the lens between tabs; release
/// to select the tab under it. Metrics and colors are measured from the native
/// tab bar in the iOS 26.5 simulator.
class GlassTabBar extends StatefulWidget {
  const GlassTabBar({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
  });

  static const double height = 62;

  final List<GlassTabItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  State<GlassTabBar> createState() => _GlassTabBarState();
}

class _GlassTabBarState extends State<GlassTabBar>
    with TickerProviderStateMixin {
  static const double _inset = 4;
  static const double _lensHeight = GlassTabBar.height + 8;

  // Snaps to the chosen tab with a small bounce.
  static final SpringDescription _settle = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 550,
    ratio: 0.68,
  );
  // Pops the lens up quickly on press, and lets it sink back on release.
  static final SpringDescription _rise = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 900,
    ratio: 0.75,
  );
  static final SpringDescription _sink = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 600,
    ratio: 0.9,
  );

  /// Center of the pill and lens along the bar while not pressed.
  late final AnimationController _x = AnimationController.unbounded(
    vsync: this,
  );

  /// 0 when resting in the bar, 1 when lifted into a lens.
  late final AnimationController _lift = AnimationController.unbounded(
    vsync: this,
  );

  /// On press, carries the lens from where it was to the finger; after that
  /// the lens is exactly under the finger.
  late final AnimationController _grab = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 150),
  );

  /// How stretched the lens is by the finger's speed, 0..1.
  late final AnimationController _stretch = AnimationController(vsync: this);
  Timer? _still;

  /// The finger's position along the bar, with resistance past the ends.
  final ValueNotifier<double> _finger = ValueNotifier<double>(0);
  final VelocityTracker _tracker = VelocityTracker.withKind(
    PointerDeviceKind.touch,
  );
  double _pressedFrom = 0;
  bool _pressed = false;

  double _width = 0;

  int get _count => widget.items.length;

  double get _pillWidth =>
      ((_width - 2 * _inset) / _count + 10).clamp(0, _width - 2 * _inset);

  double _center(int index) {
    if (_count == 1) {
      return _width / 2;
    }
    final double first = _inset + _pillWidth / 2;
    return first + index * (_width - 2 * first) / (_count - 1);
  }

  int _nearest(double x) {
    var best = 0;
    for (var i = 1; i < _count; i++) {
      if ((_center(i) - x).abs() < (_center(best) - x).abs()) {
        best = i;
      }
    }
    return best;
  }

  /// Follows the finger, resisting past the first and last tab.
  double _track(double x) {
    final double lo = _center(0), hi = _center(_count - 1);
    if (x < lo) {
      return lo - (lo - x) * 0.2;
    }
    if (x > hi) {
      return hi + (x - hi) * 0.2;
    }
    return x;
  }

  /// Where the pill and lens are now.
  double get _position => _pressed
      ? lerpDouble(
          _pressedFrom,
          _finger.value,
          Curves.easeOutCubic.transform(_grab.value),
        )!
      : _x.value;

  void _springTo(
    AnimationController c,
    double to,
    SpringDescription s, {
    double? velocity,
  }) {
    c.animateWith(SpringSimulation(s, c.value, to, velocity ?? c.velocity));
  }

  void _down(PointerDownEvent event) {
    _pressedFrom = _position;
    _x.stop();
    _pressed = true;
    _tracker.addPosition(event.timeStamp, event.localPosition);
    _finger.value = _track(event.localPosition.dx);
    _grab.forward(from: 0);
    _springTo(_lift, 1, _rise);
  }

  void _move(PointerMoveEvent event) {
    _tracker.addPosition(event.timeStamp, event.localPosition);
    _finger.value = _track(event.localPosition.dx);
    final double speed = _tracker.getVelocity().pixelsPerSecond.dx.abs();
    _stretch.animateTo(
      (speed / 2500).clamp(0.0, 1.0),
      duration: const Duration(milliseconds: 60),
    );
    _still?.cancel();
    _still = Timer(const Duration(milliseconds: 80), _relax);
  }

  void _relax() {
    _stretch.animateTo(0, duration: const Duration(milliseconds: 200));
  }

  void _up(PointerUpEvent event) => _release(_nearest(_finger.value));

  void _cancel(PointerCancelEvent event) => _release(widget.selectedIndex);

  void _release(int index) {
    final double velocity = _tracker.getVelocity().pixelsPerSecond.dx;
    _x.value = _position;
    _pressed = false;
    _grab.stop();
    _still?.cancel();
    _relax();
    _springTo(_x, _center(index), _settle, velocity: velocity);
    _springTo(_lift, 0, _sink);
    if (index != widget.selectedIndex) {
      widget.onSelected(index);
      // If the choice is not taken up, go back to the tab that is selected.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_pressed && widget.selectedIndex != index) {
          _springTo(_x, _center(widget.selectedIndex), _settle);
        }
      });
    }
  }

  @override
  void didUpdateWidget(GlassTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_pressed && oldWidget.selectedIndex != widget.selectedIndex) {
      _springTo(_x, _center(widget.selectedIndex), _settle);
    }
  }

  @override
  void dispose() {
    _x.dispose();
    _lift.dispose();
    _grab.dispose();
    _stretch.dispose();
    _still?.cancel();
    _finger.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: GlassTabBar.height,
      child: GlassBrightness(
        builder: (BuildContext context, double dark, Widget? child) =>
            _build(_Palette.lerp(_Palette.light, _Palette.dark, dark)),
      ),
    );
  }

  Widget _build(_Palette palette) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (_width != constraints.maxWidth) {
          _width = constraints.maxWidth;
          if (!_x.isAnimating && !_pressed) {
            _x.value = _center(widget.selectedIndex);
          }
        }
        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _down,
          onPointerMove: _move,
          onPointerUp: _up,
          onPointerCancel: _cancel,
          child: AnimatedBuilder(
            animation: Listenable.merge(<Listenable>[
              _x,
              _lift,
              _grab,
              _stretch,
              _finger,
            ]),
            builder: (BuildContext context, Widget? child) =>
                _buildLayers(palette),
          ),
        );
      },
    );
  }

  Widget _buildLayers(_Palette palette) {
    final double lift = _lift.value.clamp(0.0, 1.0);
    final double x = _position;
    final double pillHeight = GlassTabBar.height - 2 * _inset;

    // The lens stretches along its motion and thins a little as it does.
    final double speed = math.max(
      _stretch.value,
      (_x.velocity.abs() / 2500).clamp(0.0, 1.0),
    );
    final double stretch = 0.08 * speed * lift;
    final double lensWidth = _pillWidth * (1 + stretch);
    final double lensHeight =
        lerpDouble(pillHeight, _lensHeight, _lift.value.clamp(0.0, 1.2))! *
        (1 - stretch * 0.5);
    final Rect lens = Rect.fromCenter(
      center: Offset(x, GlassTabBar.height / 2),
      width: lensWidth,
      height: lensHeight,
    );

    Color own(int i) => i == widget.selectedIndex
        ? Color.lerp(palette.selected, palette.normal, lift)!
        : palette.normal;

    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        Positioned.fill(child: Glass(material: palette.bar)),
        Positioned(
          left: x - _pillWidth / 2,
          width: _pillWidth,
          top: _inset,
          height: pillHeight,
          child: DecoratedBox(
            decoration: ShapeDecoration(
              color: palette.pill.withValues(
                alpha: palette.pill.a * (1 - lift),
              ),
              shape: RoundedSuperellipseBorder(
                borderRadius: BorderRadius.circular(pillHeight / 2),
              ),
            ),
          ),
        ),
        ..._items(own),
        if (lift > 0.01) ...<Widget>[
          // Under the lens the items read in the accent color.
          Positioned.fill(
            child: ExcludeSemantics(
              child: ClipRRect(
                clipper: _RectClipper(lens),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: _items((_) => palette.selected),
                ),
              ),
            ),
          ),
          Positioned.fromRect(
            rect: lens,
            child: Glass(
              material: GlassMaterial.lerp(
                GlassMaterial.identity,
                palette.lens,
                lift,
              ),
            ),
          ),
        ],
      ],
    );
  }

  List<Widget> _items(Color Function(int index) colorOf) {
    return <Widget>[
      for (var i = 0; i < _count; i++)
        Positioned(
          left: _center(i) - _pillWidth / 2,
          width: _pillWidth,
          top: 0,
          bottom: 0,
          child: Semantics(
            button: true,
            selected: i == widget.selectedIndex,
            label: widget.items[i].label,
            onTap: () => widget.onSelected(i),
            child: _Tab(item: widget.items[i], color: colorOf(i)),
          ),
        ),
    ];
  }
}

class _Tab extends StatelessWidget {
  const _Tab({required this.item, required this.color});

  final GlassTabItem item;
  final Color color;

  // Item layout of the iOS 26 tab bar, read from UITabBar: the symbol's
  // alignment rect is centered 24pt below the top of the bar, and the label
  // sits in a 12pt line starting at 39pt (38.7 here, for Flutter's line
  // metrics), in semibold 10pt with SF's small-size tracking, which Flutter's
  // text engine does not apply by itself.
  static const double _symbolCenter = 24;
  static const double _labelTop = 38.7;
  static const double _labelHeight = 12;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: _symbolCenter * 2,
          child: Center(
            child: SfSymbol(item.symbol, fallback: item.icon, color: color),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: _labelTop,
          height: _labelHeight,
          child: Center(
            child: Text(
              item.label,
              maxLines: 1,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.1,
                height: 1.2,
                color: color,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _RectClipper extends CustomClipper<RRect> {
  const _RectClipper(this.rect);

  final Rect rect;

  @override
  RRect getClip(Size size) {
    return RRect.fromRectAndRadius(
      rect,
      Radius.circular(rect.shortestSide / 2),
    );
  }

  @override
  bool shouldReclip(_RectClipper oldClipper) => oldClipper.rect != rect;
}

// The lifted lens is clear, sharp glass that magnifies what is under it. Within
// a few points of its rim every pixel looks back to about the same depth, so
// the colors there are smeared outward and wrapped around the curved edge,
// splitting into color as they go. Fitted to the iOS 26 tab bar lens.
const _lens = GlassMaterial(
  refraction: 8,
  falloff: 7,
  endRefraction: 0,
  dispersion: 0.08,
  zoom: 1.25,
  blur: 0,
  saturation: 1,
  response: 1,
  lift: 0,
);
const _lensDark = GlassMaterial(
  refraction: 8,
  falloff: 7,
  endRefraction: 0,
  dispersion: 0.08,
  zoom: 1.25,
  blur: 0,
  saturation: 1,
  response: 1,
  lift: 0,
  specular: 0.4,
);

/// Colors and materials of the bar, per appearance.
class _Palette {
  const _Palette({
    required this.bar,
    required this.lens,
    required this.pill,
    required this.selected,
    required this.normal,
  });

  static const light = _Palette(
    bar: GlassMaterial.regular,
    lens: _lens,
    pill: Color(0x12000000),
    selected: Color(0xFF007EF5),
    normal: Color(0xFF191919),
  );

  static const dark = _Palette(
    bar: GlassMaterial.regularDark,
    lens: _lensDark,
    pill: Color(0x24FFFFFF),
    selected: Color(0xFF1CAEFF),
    normal: Color(0xFFF3F3F3),
  );

  static _Palette lerp(_Palette a, _Palette b, double t) {
    if (t <= 0) {
      return a;
    }
    if (t >= 1) {
      return b;
    }
    return _Palette(
      bar: GlassMaterial.lerp(a.bar, b.bar, t),
      lens: GlassMaterial.lerp(a.lens, b.lens, t),
      pill: Color.lerp(a.pill, b.pill, t)!,
      selected: Color.lerp(a.selected, b.selected, t)!,
      normal: Color.lerp(a.normal, b.normal, t)!,
    );
  }

  final GlassMaterial bar;
  final GlassMaterial lens;
  final Color pill;
  final Color selected;
  final Color normal;
}
