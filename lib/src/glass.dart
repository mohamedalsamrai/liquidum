import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'frame_sampler.dart';
import 'glass_backdrop.dart';
import 'shader_program.dart';
import 'tab_bar/appearance.dart';
import 'tab_bar/tint.dart';

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
    this.child,
  });

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
    _hub = context.dependOnInheritedWidgetOfExactType<_GlassGroupScope>()?.hub;
    _configure();
  }

  @override
  void didUpdateWidget(Glass oldWidget) {
    super.didUpdateWidget(oldWidget);
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
    _wake();
  }

  void _tick(Duration _) {
    final double now =
        SchedulerBinding.instance.currentSystemFrameTimeStamp.inMicroseconds /
        1e6;
    if (!_appearance.tick(now)) {
      _ticker.stop();
    }
    _repaint.notify();
  }

  void _wake() {
    if (!_ticker.isActive) {
      _ticker.start();
    }
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
    _sampler.dispose();
    _ticker.dispose();
    _presence.dispose();
    _repaint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _GlassSurface(
      style: widget.style,
      radius: widget.radius,
      tint: widget.tint,
      visible: widget.visible,
      presence: _presence,
      appearance: _appearance,
      hub: _hub,
      repaint: _repaint,
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
      child: widget.child,
    );
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
    _wake();
  }

  void _tick(Duration _) {
    final double now =
        SchedulerBinding.instance.currentSystemFrameTimeStamp.inMicroseconds /
        1e6;
    if (!_appearance.tick(now)) {
      _ticker.stop();
    }
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
    required this.devicePixelRatio,
    super.child,
  });

  final GlassStyle style;
  final double? radius;
  final Color? tint;
  final bool visible;
  final Animation<double> presence;
  final GlassAppearance appearance;
  final _GlassHub? hub;
  final Listenable repaint;
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
    devicePixelRatio: devicePixelRatio,
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
      ..devicePixelRatio = devicePixelRatio;
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
