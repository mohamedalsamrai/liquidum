import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'frame_sampler.dart';
import 'glass_backdrop.dart';
import 'shader_program.dart';
import 'tab_bar/appearance.dart';
import 'tab_bar/spring.dart';
import 'tab_bar/style.dart';
import 'tab_bar/tint.dart';

part 'glass_button.dart';
part 'glass_context_menu.dart';
part 'glass_menu.dart';
part 'glass_press.dart';
part 'glass_render.dart';

/// UIKit's styles of glass (`UIGlassEffect.Style`).
enum GlassStyle {
  /// Frosted glass, for bars, controls and anything with content on it.
  regular,

  /// Clearer, more refractive glass with no shadow, for glass over rich
  /// content such as photos and video.
  clear,
}

/// UIKit's glass (`UIGlassEffect`) behind [child], in a box with rounded
/// corners: a capsule unless [radius] says otherwise.
///
/// The glass is the tab bar's: it frosts what is behind it, refracts it
/// near its edge, lights its rim and casts a soft shadow, with the inputs
/// UIKit gives glass of this size and style (measured on iOS 26.5). Up to
/// 64pt in its short side it turns light or dark with what is behind it, as
/// UIKit's does, when that is wrapped in a [GlassBackdrop]; larger glass
/// follows the system's appearance.
///
/// Inside a [GlassGroup], the glass is drawn by the group, together with the
/// group's other glass, and melts into it where they are close.
///
/// Paint it after the content it floats over (for example later in a
/// [Stack]), and not inside an [Opacity], a [ShaderMask] or another save
/// layer: it reads the pixels already painted behind it.
class Glass extends StatefulWidget {
  const Glass({
    super.key,
    this.style = GlassStyle.regular,
    this.radius,
    this.tint,
    this.brightness,
    this.visible = true,
    this.interactive = false,
    this.child,
  }) : _material = null,
       _feed = null;

  // A glass button's glass, with UIKit's gray material over it.
  const Glass._button(
    this._material, {
    required this.style,
    required this.tint,
    required this.interactive,
    required this.child,
  }) : radius = null,
       brightness = null,
       visible = true,
       _feed = null;

  // A menu's glass: interactive, also pressed by a finger that went down
  // elsewhere (on the button that opened it) and slid onto it.
  const Glass._fed(
    this._feed, {
    required this.radius,
    required this.brightness,
    required this.interactive,
    required this.child,
  }) : style = GlassStyle.regular,
       tint = null,
       visible = true,
       _material = null;

  final GlassStyle style;

  /// The corners' radius. A capsule (half the short side) when null.
  final double? radius;

  /// Tints the glass, as `UIGlassEffect.tintColor`: the glass takes the
  /// color, deeper where it is darker. The color's alpha sets how strongly.
  final Color? tint;

  /// Forces the light or the dark appearance. By default small glass follows
  /// what is behind it, and large glass the system. Inside a [GlassGroup],
  /// the group's [GlassGroup.brightness] applies instead.
  final Brightness? brightness;

  /// Whether the glass shows. Changing it materializes or dematerializes the
  /// glass, as UIKit's when its effect is set or cleared in an animation:
  /// its blur, refraction, color, rim and shadow grow from nothing (or fade
  /// to nothing) together, over half a second, easing in and out. The glass
  /// keeps its size throughout. In a [GlassGroup], appearing glass melts
  /// into its neighbors at once, and disappearing glass leaves them at once.
  ///
  /// Only the glass: [child] stays.
  final bool visible;

  /// Whether the glass responds to a finger, as UIKit's interactive glass
  /// (`UIGlassEffect.isInteractive`, and glass buttons): pressed, it swells
  /// (with [child]), lightens and glows under the finger, stretches toward
  /// a drag, and springs back when let go. It takes no gesture away from
  /// [child]: a button inside still gets its taps.
  ///
  /// As UIKit's, by its size: glass up to 110pt long swells by 16pt and
  /// glows fully; longer glass swells less and glows more faintly the
  /// taller it is (4pt and a fifth from 160pt).
  final bool interactive;

  final _GlassMaterial? _material;
  final _GlassPressFeed? _feed;

  final Widget? child;

  /// How long the glass takes to materialize or dematerialize.
  static const Duration materializeDuration = Duration(milliseconds: 500);

  static final ShaderProgram _program = ShaderProgram('glass.frag');

  /// Loads the glass shader ahead of time. Optional: glass loads it itself,
  /// and appears once it is in.
  static Future<void> precache() => _program.load();

  @override
  State<Glass> createState() => _GlassState();
}

class _GlassState extends State<Glass> with TickerProviderStateMixin {
  final GlassAppearance _appearance = GlassAppearance();
  late final Ticker _ticker = createTicker(_tick);
  late final FrameSampler _sampler;
  late final AnimationController _presence = AnimationController(
    vsync: this,
    duration: Glass.materializeDuration,
    value: widget.visible ? 1 : 0,
  );
  final _Repaint _repaint = _Repaint();
  _GlassHub? _hub;
  bool _sampling = false;
  _GlassPress? _press;

  /// Whether the glass looks dark, for what is drawn on it.
  final ValueNotifier<bool> _dark = ValueNotifier<bool>(false);

  @override
  void initState() {
    super.initState();
    if (widget.interactive) {
      _press = _GlassPress();
    }
    widget._feed?._glass = this;
    _sampler = FrameSampler(
      interval: const Duration(milliseconds: 50),
      sample: _sample,
    );
    Glass._program.load().then((_) {
      if (mounted) {
        _repaint.notify();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _hub = context.dependOnInheritedWidgetOfExactType<_GlassGroupScope>()?.hub;
    _configure();
  }

  @override
  void didUpdateWidget(Glass oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget._feed != widget._feed) {
      if (oldWidget._feed?._glass == this) {
        oldWidget._feed!._glass = null;
      }
      widget._feed?._glass = this;
    }
    if (widget.interactive != oldWidget.interactive) {
      _press?.dispose();
      _press = widget.interactive ? _GlassPress() : null;
    }
    if (widget.visible != oldWidget.visible) {
      if (widget.visible) {
        _presence.forward();
      } else {
        _presence.reverse();
      }
    }
    _configure();
  }

  void _configure() {
    final Brightness? forced = widget.brightness;
    _appearance
      ..adaptive = forced == null
      ..system = forced ?? MediaQuery.platformBrightnessOf(context);
    _dark.value = _appearance.isDark;
    _wake();
  }

  void _tick(Duration _) {
    final double now =
        SchedulerBinding.instance.currentSystemFrameTimeStamp.inMicroseconds /
        1e6;
    final bool appearing = _appearance.tick(now);
    final bool pressing = _press?.tick(now) ?? false;
    _dark.value = _appearance.isDark;
    if (!appearing && !pressing) {
      _ticker.stop();
    }
    _repaint.notify();
  }

  void _wake() {
    if (!_ticker.isActive) {
      _ticker.start();
    }
  }

  // A finger from elsewhere, in global coordinates.
  void _fedDown(Offset global) {
    final _GlassPress? press = _press;
    final RenderObject? box = context.findRenderObject();
    if (press == null || press.pressed || box is! RenderBox) {
      return;
    }
    press.down(box.globalToLocal(global));
    _wake();
  }

  void _fedMove(Offset global) {
    final RenderObject? box = context.findRenderObject();
    if (box is RenderBox) {
      _press?.move(box.globalToLocal(global));
      _wake();
    }
  }

  void _fedUp() {
    _press?.up();
    _wake();
  }

  void _down(PointerDownEvent event) {
    final _GlassPress? press = _press;
    if (press == null || press.pressed) {
      return;
    }
    press.down(event.localPosition);
    _wake();
  }

  void _move(PointerMoveEvent event) {
    _press?.move(event.localPosition);
    _wake();
  }

  void _up(PointerEvent event) {
    _press?.up();
    _wake();
  }

  // Reads the backdrop under small glass, as the bar does; large glass and
  // clear glass do not follow it, and a group reads its own.
  Future<void> _sample() async {
    if (_sampling ||
        !mounted ||
        _hub != null ||
        _presence.value == 0 ||
        _appearance.isLarge ||
        widget.style == GlassStyle.clear) {
      return;
    }
    final RenderObject? box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) {
      return;
    }
    final Rect rect = MatrixUtils.transformRect(
      box.getTransformTo(null),
      Offset.zero & box.size,
    );
    final GlassBackdropState? backdrop = glassBackdropUnder(rect);
    if (backdrop == null) {
      return;
    }
    _sampling = true;
    try {
      final double? luma = await backdrop.meanLuma(
        GlassAppearance.glassSampleArea(rect),
      );
      if (mounted && luma != null && !_appearance.wouldKeep(luma)) {
        // Glass materializing shows its default look, then adapts.
        _appearance.sample(luma, snap: _presence.value == 1);
        _wake();
      }
    } finally {
      _sampling = false;
    }
  }

  @override
  void dispose() {
    if (widget._feed?._glass == this) {
      widget._feed!._glass = null;
    }
    _sampler.dispose();
    _ticker.dispose();
    _presence.dispose();
    _repaint.dispose();
    _press?.dispose();
    _dark.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget glass = _GlassSurface(
      hidden:
          context
              .dependOnInheritedWidgetOfExactType<_GlassHiddenScope>()
              ?.hidden ??
          false,
      style: widget.style,
      radius: widget.radius,
      tint: widget.tint,
      visible: widget.visible,
      presence: _presence,
      appearance: _appearance,
      hub: _hub,
      repaint: _repaint,
      press: _press,
      material: widget._material,
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
      child: widget.child == null
          ? null
          : _GlassTone(
              // In a group, the group's look.
              dark: switch (_hub) {
                null => _dark,
                final _GlassHub hub =>
                  widget.style == GlassStyle.clear ? hub.clearDark : hub.dark,
              },
              child: _press == null
                  ? widget.child!
                  : _GlassPressScope(
                      press: _GlassPressView._(_press!),
                      child: widget.child!,
                    ),
            ),
    );
    final _GlassPress? press = _press;
    if (press != null) {
      glass = Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _down,
        onPointerMove: _move,
        onPointerUp: _up,
        onPointerCancel: _up,
        child: _PressTransform(press: press, child: glass),
      );
    }
    return glass;
  }
}

/// UIKit's glass container (`UIGlassContainerEffect`): the [Glass] in
/// [child] is drawn as one glass, whose shapes melt together where they
/// come within [spacing] of each other.
///
/// The shapes join through a smooth neck when their gap is under half the
/// spacing, and lean toward each other a little before; surfaces that face
/// each other melt the most, side by side not at all (UIKit's union, fitted
/// to its outlines within 0.1pt on iOS 26.5). The group's glass has one set
/// of inputs, as UIKit's: the refraction and frost depth of its smallest
/// glass, and the blur, shadow and large-glass look of its largest; small
/// groups turn light or dark together, with what is behind all their glass.
/// Regular and clear glass in one group are drawn apart and do not melt.
/// Each tint stays with its own glass, reaching a little into a neck.
///
/// Up to eight shapes of a style melt together; more are drawn in further
/// groups of eight. Paint the group after the content its glass floats
/// over: its glass is painted where the group is in the paint order, before
/// anything in [child].
class GlassGroup extends StatefulWidget {
  const GlassGroup({
    super.key,
    this.spacing = 0,
    this.brightness,
    required this.child,
  });

  /// How close glass must come to melt (points): UIKit's `spacing`, 0 by
  /// default (glass melts only where it touches).
  final double spacing;

  /// Forces the light or the dark appearance. By default small groups follow
  /// what is behind their glass, and large ones the system.
  final Brightness? brightness;

  final Widget child;

  @override
  State<GlassGroup> createState() => _GlassGroupState();
}

class _GlassGroupState extends State<GlassGroup>
    with SingleTickerProviderStateMixin {
  final GlassAppearance _appearance = GlassAppearance();
  // Clear glass is a glass group of its own in UIKit, which does not follow
  // what is behind it: the system's appearance.
  final GlassAppearance _clearAppearance = GlassAppearance()..adaptive = false;
  final _GlassHub _hub = _GlassHub();
  late final Ticker _ticker = createTicker(_tick);
  late final FrameSampler _sampler;
  final _Repaint _repaint = _Repaint();
  bool _sampling = false;

  @override
  void initState() {
    super.initState();
    _sampler = FrameSampler(
      interval: const Duration(milliseconds: 50),
      sample: _sample,
    );
    Glass._program.load().then((_) {
      if (mounted) {
        _repaint.notify();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _configure();
  }

  @override
  void didUpdateWidget(GlassGroup oldWidget) {
    super.didUpdateWidget(oldWidget);
    _configure();
  }

  void _configure() {
    final Brightness? forced = widget.brightness;
    _appearance
      ..adaptive = forced == null
      ..system = forced ?? MediaQuery.platformBrightnessOf(context);
    _clearAppearance.system =
        forced ?? MediaQuery.platformBrightnessOf(context);
    _hub.dark.value = _appearance.isDark;
    _hub.clearDark.value = _clearAppearance.isDark;
    _wake();
  }

  void _tick(Duration _) {
    final double now =
        SchedulerBinding.instance.currentSystemFrameTimeStamp.inMicroseconds /
        1e6;
    if (!_appearance.tick(now)) {
      _ticker.stop();
    }
    _hub.dark.value = _appearance.isDark;
    _repaint.notify();
  }

  void _wake() {
    if (!_ticker.isActive) {
      _ticker.start();
    }
  }

  // Reads the backdrop under the group's small regular glass, as one: the
  // mean of each glass's own sample area, by area.
  Future<void> _sample() async {
    if (_sampling || !mounted || _appearance.isLarge) {
      return;
    }
    final List<Rect> rects = <Rect>[
      for (final _RenderGlass glass in _hub.members)
        if (glass.attached &&
            glass.hasSize &&
            glass.style == GlassStyle.regular &&
            glass.amount > 0)
          MatrixUtils.transformRect(
            glass.getTransformTo(null),
            Offset.zero & glass.size,
          ),
    ];
    if (rects.isEmpty) {
      return;
    }
    final GlassBackdropState? backdrop = glassBackdropUnder(
      rects.reduce((Rect a, Rect b) => a.expandToInclude(b)),
    );
    if (backdrop == null) {
      return;
    }
    _sampling = true;
    try {
      var sum = 0.0;
      var weight = 0.0;
      for (final Rect rect in rects) {
        final Rect area = GlassAppearance.glassSampleArea(rect);
        final double? luma = await backdrop.meanLuma(area);
        if (luma == null) {
          return;
        }
        sum += luma * area.width * area.height;
        weight += area.width * area.height;
      }
      final double luma = sum / weight;
      if (mounted && !_appearance.wouldKeep(luma)) {
        _appearance.sample(
          luma,
          snap: _hub.members.every((_RenderGlass g) => g.amount == 1),
        );
        _wake();
      }
    } finally {
      _sampling = false;
    }
  }

  @override
  void dispose() {
    _sampler.dispose();
    _ticker.dispose();
    _repaint.dispose();
    _hub.dark.dispose();
    _hub.clearDark.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _GlassGroupScope(
      hub: _hub,
      child: _GlassGroupSurface(
        hub: _hub,
        spacing: widget.spacing,
        appearance: _appearance,
        clearAppearance: _clearAppearance,
        repaint: _repaint,
        devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
        child: widget.child,
      ),
    );
  }
}

class _Repaint extends ChangeNotifier {
  void notify() => notifyListeners();
}

/// What a group's glass and its render object share: the glass in it.
class _GlassHub {
  final Set<_RenderGlass> members = <_RenderGlass>{};
  _RenderGlassGroup? group;

  /// Whether the group's regular and clear glass look dark now: what the
  /// content on its glass follows (glass in a group takes the group's look).
  final ValueNotifier<bool> dark = ValueNotifier<bool>(false);
  final ValueNotifier<bool> clearDark = ValueNotifier<bool>(false);

  void add(_RenderGlass glass) {
    members.add(glass);
    changed();
  }

  void remove(_RenderGlass glass) {
    members.remove(glass);
    changed();
  }

  void changed() {
    final _RenderGlassGroup? g = group;
    if (g != null && g.attached) {
      g.markNeedsPaint();
    }
  }
}

class _GlassGroupScope extends InheritedWidget {
  const _GlassGroupScope({required this.hub, required super.child});

  final _GlassHub hub;

  @override
  bool updateShouldNotify(_GlassGroupScope oldWidget) => hub != oldWidget.hub;
}

class _GlassSurface extends SingleChildRenderObjectWidget {
  const _GlassSurface({
    required this.style,
    required this.radius,
    required this.tint,
    required this.visible,
    required this.presence,
    required this.appearance,
    required this.hub,
    required this.repaint,
    required this.press,
    required this.material,
    required this.devicePixelRatio,
    this.hidden = false,
    super.child,
  });

  final bool hidden;
  final GlassStyle style;
  final double? radius;
  final Color? tint;
  final bool visible;
  final Animation<double> presence;
  final GlassAppearance appearance;
  final _GlassHub? hub;
  final Listenable repaint;
  final _GlassPress? press;
  final _GlassMaterial? material;
  final double devicePixelRatio;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderGlass(
    style: style,
    radius: radius,
    tint: tint,
    visible: visible,
    presence: presence,
    appearance: appearance,
    hub: hub,
    repaint: repaint,
    press: press,
    material: material,
    devicePixelRatio: devicePixelRatio,
    hidden: hidden,
  );

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderGlass)
      ..style = style
      ..radius = radius
      ..tint = tint
      ..visible = visible
      ..presence = presence
      ..hub = hub
      ..repaint = repaint
      ..press = press
      ..material = material
      ..devicePixelRatio = devicePixelRatio
      ..hidden = hidden;
  }
}

class _GlassGroupSurface extends SingleChildRenderObjectWidget {
  const _GlassGroupSurface({
    required this.hub,
    required this.spacing,
    required this.appearance,
    required this.clearAppearance,
    required this.repaint,
    required this.devicePixelRatio,
    super.child,
  });

  final _GlassHub hub;
  final double spacing;
  final GlassAppearance appearance;
  final GlassAppearance clearAppearance;
  final Listenable repaint;
  final double devicePixelRatio;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderGlassGroup(
    hub: hub,
    spacing: spacing,
    appearance: appearance,
    clearAppearance: clearAppearance,
    repaint: repaint,
    devicePixelRatio: devicePixelRatio,
  );

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderGlassGroup)
      ..spacing = spacing
      ..repaint = repaint
      ..devicePixelRatio = devicePixelRatio;
  }
}

/// Whether the glass around its child looks dark, for what is drawn on it
/// (a [GlassButton]'s label follows it, as UIKit's vibrant labels do).
class _GlassTone extends InheritedNotifier<ValueNotifier<bool>> {
  const _GlassTone({required ValueNotifier<bool> dark, required super.child})
    : super(notifier: dark);
}

/// Whether the nearest glass above [context] looks dark (null outside
/// glass). Rebuilds [context] when it turns.
bool? _glassIsDarkOf(BuildContext context) =>
    context.dependOnInheritedWidgetOfExactType<_GlassTone>()?.notifier?.value;

/// How pressed interactive glass is, for what is drawn on it (a glass
/// button's label dims while pressed). Notifies as the press moves.
class _GlassPressView {
  _GlassPressView._(this._press);

  final _GlassPress _press;

  Listenable get listenable => _press;

  /// How pressed the glass is, 0 to 1 (its wash and glow follow).
  double get amount => _press.amount;

  @override
  bool operator ==(Object other) =>
      other is _GlassPressView && other._press == _press;

  @override
  int get hashCode => _press.hashCode;
}

class _GlassPressScope extends InheritedWidget {
  const _GlassPressScope({required this.press, required super.child});

  final _GlassPressView press;

  @override
  bool updateShouldNotify(_GlassPressScope oldWidget) =>
      press != oldWidget.press;
}

/// The press of the nearest interactive glass above [context], if any.
_GlassPressView? _glassPressOf(BuildContext context) =>
    context.dependOnInheritedWidgetOfExactType<_GlassPressScope>()?.press;

/// Hides the [Glass] below at once (its glass, not its content): a menu's
/// source while the menu that grew out of it is open.
class _GlassHiddenScope extends InheritedWidget {
  const _GlassHiddenScope({required this.hidden, required super.child});

  final bool hidden;

  @override
  bool updateShouldNotify(_GlassHiddenScope oldWidget) =>
      hidden != oldWidget.hidden;
}
