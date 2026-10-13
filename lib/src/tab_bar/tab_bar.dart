import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../shader_program.dart';
import 'physics.dart';

/// A tab in a [GlassTabBar].
@immutable
class GlassTabItem {
  const GlassTabItem({required this.icon, required this.label});

  /// Drawn centered in the tab's symbol area. It should take its color from
  /// the ambient [IconTheme], which the bar sets for normal and selected
  /// tabs (as [Icon] does).
  final Widget icon;

  final String label;
}

/// What [GlassTabBar] draws for its glass while it is being built up.
enum GlassTabBarDebugView {
  /// The glass: the bar's pass and the lens's pass over one shared backdrop
  /// capture (neutral placeholders until the optics are in).
  none,

  /// The glass field flat: platter, pill and lens silhouettes.
  field,

  /// The lens's surface normals as colors.
  normals,

  /// The sampling architecture made visible: the bar's glass hatched (so a
  /// pass reading rendered glass would show it), the lens pass marking what
  /// it shows from outside itself, an inspector with the capture both passes
  /// read, and the glass field, sampling region and finger drawn twice (by
  /// the shaders in capture pixels, and by the canvas in layout
  /// coordinates) so that any mismatch shows.
  sampling,
}

/// The optical stages of the glass, as bits of [GlassTabBar.debugOptics].
abstract final class GlassTabBarOptics {
  /// The lens's warp: samples pushed outward near its edge.
  static const int warp = 1;

  /// The lens's inner refraction, and its material's tone.
  static const int inner = 2;

  /// The lens's chromatic dispersion.
  static const int dispersion = 4;

  /// The platter's material (refraction, frost, color); without it, the
  /// backdrop is seen bare.
  static const int platter = 8;

  /// The resting selection's tint.
  static const int rest = 16;

  /// The lifted content: the selected tab grown and lensed by the lens.
  static const int content = 32;

  /// The lit rims of the platter and the lens.
  static const int rim = 64;

  /// The shadows of the platter and the lens.
  static const int shadow = 128;

  /// The press: the wash over the platter and the fingertip glow.
  static const int press = 256;

  static const int all = 511;
}

/// An iOS 26 tab bar: a glass platter holding the tabs, and a lens that
/// selects one. Press and slide to carry the lens between tabs; release to
/// select the tab under it.
class GlassTabBar extends StatefulWidget {
  const GlassTabBar({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    this.debugView = GlassTabBarDebugView.none,
    this.debugShareBackdrop = true,
    this.debugInspector,
    this.debugHold,
    this.debugHideContent = false,
    this.debugOptics = GlassTabBarOptics.all,
    this.debugLift,
  });

  /// Height of the bar, as on iOS 26.
  static const double height = 62;

  final List<GlassTabItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final GlassTabBarDebugView debugView;

  /// Whether the lens reads the same backdrop capture as the bar, taken
  /// before any of the bar's glass. Turn off only to see what the lens would
  /// read otherwise: the bar's rendered glass.
  final bool debugShareBackdrop;

  /// Where [GlassTabBarDebugView.sampling] draws its inspector, in the bar's
  /// coordinates. Defaults to a panel above the bar.
  final Rect? debugInspector;

  /// Holds a press at this point, in the bar's coordinates, from the first
  /// frame on: the lens stays lifted there without a real touch, for still
  /// comparisons.
  final Offset? debugHold;

  /// Draws no tab content, so the glass's optics can be looked at alone.
  final bool debugHideContent;

  /// The optical stages drawn (a [GlassTabBarOptics] mask), to compare them
  /// one at a time.
  final int debugOptics;

  /// Draws the glass's optics at this lift progress (0 to 1) instead of the
  /// lens's, to compare the transition between resting and lifted at fixed
  /// points.
  final double? debugLift;

  static final ShaderProgram _field = ShaderProgram('field.frag');
  static final ShaderProgram _backdrop = ShaderProgram('backdrop.frag');

  /// Loads the bar's shaders ahead of time, so the first frame has them.
  static Future<void> precache() =>
      Future.wait(<Future<void>>[_field.load(), _backdrop.load()]);

  @override
  State<GlassTabBar> createState() => _GlassTabBarState();
}

class _GlassTabBarState extends State<GlassTabBar>
    with SingleTickerProviderStateMixin {
  late final GlassTabBarPhysics _physics = GlassTabBarPhysics(
    count: widget.items.length,
    selectedIndex: widget.selectedIndex,
  );
  late final Ticker _ticker = createTicker(_tick);
  final _Frame _frame = _Frame();
  int? _pointer;

  // The raw vsync time: on the same clock as pointer event time stamps, so
  // touches take effect at the moment they happened.
  static double get _frameTime =>
      SchedulerBinding.instance.currentSystemFrameTimeStamp.inMicroseconds /
      1e6;

  static double _timeOf(PointerEvent event) =>
      event.timeStamp.inMicroseconds / 1e6;

  void _tick(Duration _) {
    if (!_physics.tick(_frameTime)) {
      _ticker.stop();
    }
    _frame.notify();
  }

  void _wake() {
    if (!_ticker.isActive) {
      _ticker.start();
    }
  }

  void _handlePointer(PointerEvent event) {
    switch (event) {
      case PointerDownEvent():
        if (_pointer != null) {
          return;
        }
        _pointer = event.pointer;
        _physics.pointerDown(event.localPosition, time: _timeOf(event));
      case PointerMoveEvent():
        if (event.pointer != _pointer) {
          return;
        }
        _physics.pointerMove(event.localPosition, time: _timeOf(event));
      case PointerUpEvent():
        if (event.pointer != _pointer) {
          return;
        }
        _pointer = null;
        final int index = _physics.pointerUp(time: _timeOf(event));
        if (index != widget.selectedIndex) {
          widget.onSelected(index);
          // If the choice is not taken up, go back to the selected tab.
          SchedulerBinding.instance.addPostFrameCallback((_) {
            if (mounted &&
                _pointer == null &&
                _physics.selectedIndex != widget.selectedIndex) {
              _physics.select(widget.selectedIndex);
              _wake();
            }
          });
        }
      case PointerCancelEvent():
        if (event.pointer != _pointer) {
          return;
        }
        _pointer = null;
        _physics.pointerCancel(time: _timeOf(event));
      default:
        return;
    }
    _wake();
  }

  @override
  void initState() {
    super.initState();
    GlassTabBar.precache().then((_) {
      if (mounted) {
        _frame.notify();
      }
    });
    final Offset? hold = widget.debugHold;
    if (hold != null) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _physics.pointerDown(hold);
          _wake();
        }
      });
    }
  }

  @override
  void didUpdateWidget(GlassTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedIndex != _physics.selectedIndex) {
      _physics.select(widget.selectedIndex);
      _wake();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  // Colors of the iOS 26 tab bar in light mode.
  static const Color _normal = Color(0xFF191919);
  static const Color _selected = Color(0xFF007EF5);

  @override
  Widget build(BuildContext context) {
    final List<GlassTabItem> items = widget.items;
    const hidden = Color(0x00000000);
    final Color normal = widget.debugHideContent ? hidden : _normal;
    final Color selected = widget.debugHideContent ? hidden : _selected;
    return SizedBox(
      height: GlassTabBar.height,
      child: _TabBarLayout(
        physics: _physics,
        frame: _frame,
        onPointer: _handlePointer,
        debugView: widget.debugView,
        shareBackdrop: widget.debugShareBackdrop,
        inspector: widget.debugInspector,
        optics: widget.debugOptics,
        lift: widget.debugLift,
        devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
        children: <Widget>[
          for (var i = 0; i < items.length; i++)
            Semantics(
              button: true,
              selected: i == widget.selectedIndex,
              label: items[i].label,
              onTap: () => widget.onSelected(i),
              child: ExcludeSemantics(
                child: _TabView(item: items[i], color: normal),
              ),
            ),
          for (var i = 0; i < items.length; i++)
            ExcludeSemantics(
              child: _TabView(item: items[i], color: selected),
            ),
        ],
      ),
    );
  }
}

class _Frame extends ChangeNotifier {
  void notify() => notifyListeners();
}

/// One tab's symbol and label, laid out as UITabBar does on iOS 26: the
/// symbol's alignment rect centered 24pt below the top of the bar, and the
/// label in a 12pt line from 39pt (38.7 here, for Flutter's line metrics),
/// semibold 10pt with SF's small-size tracking, which Flutter's text engine
/// does not apply by itself.
class _TabView extends StatelessWidget {
  const _TabView({required this.item, required this.color});

  final GlassTabItem item;
  final Color color;

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
            child: IconTheme.merge(
              data: IconThemeData(color: color, size: 26),
              child: item.icon,
            ),
          ),
        ),
        Positioned(
          left: -20,
          right: -20,
          top: _labelTop,
          height: _labelHeight,
          child: Center(
            child: Text(
              item.label,
              maxLines: 1,
              softWrap: false,
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

class _TabBarLayout extends MultiChildRenderObjectWidget {
  const _TabBarLayout({
    required this.physics,
    required this.frame,
    required this.onPointer,
    required this.debugView,
    required this.shareBackdrop,
    required this.inspector,
    required this.optics,
    required this.lift,
    required this.devicePixelRatio,
    required super.children,
  });

  final GlassTabBarPhysics physics;
  final Listenable frame;
  final ValueChanged<PointerEvent> onPointer;
  final GlassTabBarDebugView debugView;
  final bool shareBackdrop;
  final Rect? inspector;
  final int optics;
  final double? lift;
  final double devicePixelRatio;

  @override
  RenderGlassTabBar createRenderObject(BuildContext context) {
    return RenderGlassTabBar(
      physics: physics,
      frame: frame,
      onPointer: onPointer,
      debugView: debugView,
      shareBackdrop: shareBackdrop,
      inspector: inspector,
      optics: optics,
      lift: lift,
      devicePixelRatio: devicePixelRatio,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderGlassTabBar renderObject,
  ) {
    renderObject
      ..onPointer = onPointer
      ..debugView = debugView
      ..shareBackdrop = shareBackdrop
      ..inspector = inspector
      ..optics = optics
      ..lift = lift
      ..devicePixelRatio = devicePixelRatio;
  }
}

class _TabParentData extends ContainerBoxParentData<RenderBox> {}

/// Lays out a [GlassTabBar]'s tabs (each twice: normal, then in the
/// selected color), takes its touches, and paints the glass and the tabs
/// where [GlassTabBarPhysics] puts them.
///
/// The glass is two passes over one backdrop capture. The bar's pass comes
/// first and takes the capture: everything behind the bar, before any of its
/// glass. The lens's pass comes after the tabs and reads that same capture
/// (a shared [BackdropKey]), so it can reach content far outside itself but
/// never sees the bar's glass, the tabs, or itself. The tabs under the lens
/// are not painted here but lifted into it: the lens's shader draws them
/// from an atlas of the tabs in the selected style, grown and lensed.
class RenderGlassTabBar extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _TabParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _TabParentData> {
  RenderGlassTabBar({
    required this._physics,
    required this._frame,
    required this.onPointer,
    required this._debugView,
    required this._shareBackdrop,
    required this._inspector,
    this._optics = GlassTabBarOptics.all,
    this._lift,
    required this._devicePixelRatio,
  });

  final GlassTabBarPhysics _physics;
  final Listenable _frame;
  ValueChanged<PointerEvent> onPointer;

  GlassTabBarDebugView get debugView => _debugView;
  GlassTabBarDebugView _debugView;
  set debugView(GlassTabBarDebugView value) {
    if (value != _debugView) {
      _debugView = value;
      markNeedsCompositingBitsUpdate();
      markNeedsPaint();
    }
  }

  bool get shareBackdrop => _shareBackdrop;
  bool _shareBackdrop;
  set shareBackdrop(bool value) {
    if (value != _shareBackdrop) {
      _shareBackdrop = value;
      markNeedsPaint();
    }
  }

  Rect? get inspector => _inspector;
  Rect? _inspector;
  set inspector(Rect? value) {
    if (value != _inspector) {
      _inspector = value;
      markNeedsPaint();
    }
  }

  /// The optical stages drawn: a [GlassTabBarOptics] mask.
  int get optics => _optics;
  int _optics;
  set optics(int value) {
    if (value != _optics) {
      _optics = value;
      markNeedsPaint();
    }
  }

  /// The lift progress the optics are drawn at, when not the lens's own.
  double? get lift => _lift;
  double? _lift;
  set lift(double? value) {
    if (value != _lift) {
      _lift = value;
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

  ui.FragmentShader? _fieldShader;

  // One shader per pass: a shader image filter reads its uniforms only when
  // it is composited, after all passes have been painted.
  final List<_BackdropUniforms> _passes = <_BackdropUniforms>[];

  // One capture for the bar and the lens (and the inspector); a second key
  // only for the comparison where the lens reads the bar's glass.
  final BackdropKey _sharedCapture = BackdropKey();
  final BackdropKey _lensOwnCapture = BackdropKey();

  final LayerHandle<ClipRectLayer> _barClip = LayerHandle<ClipRectLayer>();
  final LayerHandle<BackdropFilterLayer> _barPass =
      LayerHandle<BackdropFilterLayer>();
  final LayerHandle<ClipRectLayer> _lensClip = LayerHandle<ClipRectLayer>();
  final LayerHandle<BackdropFilterLayer> _lensPass =
      LayerHandle<BackdropFilterLayer>();
  final LayerHandle<ClipRectLayer> _inspectorClip =
      LayerHandle<ClipRectLayer>();
  final LayerHandle<BackdropFilterLayer> _inspectorPass =
      LayerHandle<BackdropFilterLayer>();

  bool get _drawsGlass =>
      (_debugView == GlassTabBarDebugView.none ||
          _debugView == GlassTabBarDebugView.sampling) &&
      ui.ImageFilter.isShaderFilterSupported;

  @override
  bool get alwaysNeedsCompositing => _drawsGlass;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _TabParentData) {
      child.parentData = _TabParentData();
    }
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _frame.addListener(_onFrame);
  }

  @override
  void detach() {
    _frame.removeListener(_onFrame);
    super.detach();
  }

  // A new animation frame repaints the glass, not the tabs' content.
  bool _repaintingFrame = false;
  void _onFrame() {
    _repaintingFrame = true;
    markNeedsPaint();
    _repaintingFrame = false;
  }

  @override
  void markNeedsPaint() {
    // Anything else (a tab's content changing, a new layout, a setting) may
    // change what the lens shows of the tabs.
    if (!_repaintingFrame) {
      _contentDirty = true;
    }
    super.markNeedsPaint();
  }

  @override
  void dispose() {
    _contentAtlas?.dispose();
    _noContent?.dispose();
    _fieldShader?.dispose();
    for (final _BackdropUniforms u in _passes) {
      u.shader.dispose();
    }
    _clearGlassLayers();
    super.dispose();
  }

  void _clearGlassLayers() {
    _barClip.layer = null;
    _barPass.layer = null;
    _lensClip.layer = null;
    _lensPass.layer = null;
    _inspectorClip.layer = null;
    _inspectorPass.layer = null;
    _washLayer.layer = null;
    _glowClip.layer = null;
  }

  int get _tabCount => childCount ~/ 2;

  @override
  void performLayout() {
    _contentDirty = true;
    size = constraints.constrain(
      Size(constraints.maxWidth, GlassTabBar.height),
    );
    final int count = _tabCount;
    if (count == 0) {
      return;
    }
    _physics.layout(size, count);
    final double width = _physics.pillWidth;
    final tight = BoxConstraints.tight(Size(width, size.height));
    var i = 0;
    RenderBox? child = firstChild;
    while (child != null) {
      child.layout(tight);
      (child.parentData! as _TabParentData).offset = Offset(
        _physics.tabCenter(i % count) - width / 2,
        0,
      );
      child = childAfter(child);
      i++;
    }
  }

  @override
  bool hitTestSelf(Offset position) => size.contains(position);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      false;

  @override
  void handleEvent(PointerEvent event, BoxHitTestEntry entry) {
    onPointer(event);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_tabCount == 0) {
      return;
    }
    final ui.FragmentProgram? program = GlassTabBar._backdrop.program;
    if (!_drawsGlass || program == null) {
      _clearGlassLayers();
      _paintField(context.canvas, offset);
      context.pushTransform(
        needsCompositing,
        offset,
        _physics.platterTransform,
        _paintTabs,
      );
      return;
    }
    _paintGlass(context, offset, program);
  }

  // --------------------------------------------------------------- the glass

  void _paintGlass(
    PaintingContext context,
    Offset offset,
    ui.FragmentProgram program,
  ) {
    final bool diagnostic = _debugView == GlassTabBarDebugView.sampling;
    while (_passes.length < 3) {
      _passes.add(_BackdropUniforms(program.fragmentShader()));
    }
    final _CaptureSpace space = _CaptureSpace(
      getTransformTo(null),
      _devicePixelRatio,
    );
    final Rect platter = _physics.platterRect;
    final Rect lens = _physics.lensRect;
    final Offset? touch = _physics.touch;

    // The same geometry for every pass, in capture pixels.
    final Rect platterPixels = space.rect(platter);
    final Rect lensPixels = space.rect(lens);
    final Offset finger = touch == null ? Offset.zero : space.point(touch);
    final Rect inspector = _inspectorRect;
    final Rect inspectorPixels = space.rect(inspector);
    final Rect window = space.rect(
      Rect.fromCenter(
        center: lens.center,
        width: inspector.width / _inspectorZoom,
        height: inspector.height / _inspectorZoom,
      ),
    );

    // The glass's optics are in its own points: the lens is drawn scaled by
    // the platter and by its flex, the platter by its swell and stretch.
    final double platterScale = math.sqrt(
      _physics.platterScaleX * _physics.platterScaleY,
    );
    final Size flex = _physics.flexScale;
    final double lensScale = platterScale * math.sqrt(flex.width * flex.height);

    // The tabs in the selected style, which the lens draws itself.
    final ui.Image atlas = _ensureContentAtlas();
    final Offset barOrigin = space.point(Offset.zero);
    final Offset platterCenter = size.center(Offset.zero);
    final Offset drift = _physics.platterDrift;
    final int count = _tabCount;

    // The fingertip glow, for the lens's view of it: a gaussian of the
    // blurred disk's peak and volume.
    final Offset? glowCenter = _physics.glowCenter;
    final double glowAlpha = _optics & GlassTabBarOptics.press != 0
        ? _physics.glowAlpha
        : 0;
    final double glowRadius = space.pointSize * _physics.glowSize / 2;
    final double glowSigma = space.pointSize * _physics.glowSigma;
    final double glowPeak =
        1 - math.exp(-glowRadius * glowRadius / (2 * glowSigma * glowSigma));
    final double glowVariance = glowRadius * glowRadius / (2 * glowPeak);
    final Offset glowPixels = glowCenter == null
        ? Offset.zero
        : space.point(glowCenter);

    ui.ImageFilter passFilter(int pass) {
      final _BackdropUniforms u = _passes[pass]
        ..pass.set(
          pass.toDouble(),
          diagnostic ? 1 : 0,
          space.pointSize,
          _ovalization,
        )
        ..platter.setRect(platterPixels)
        ..lens.setRect(lensPixels)
        ..optics.set(
          _lift ?? _physics.liftProgress,
          lensScale,
          platterScale,
          _optics.toDouble(),
        )
        ..touch.set(finger.dx, finger.dy, touch == null ? 0 : 1, _physics.press)
        ..inspector.set(
          inspectorPixels.left,
          inspectorPixels.top,
          inspectorPixels.width,
          inspectorPixels.height,
        )
        ..window.set(window.left, window.top, window.width, window.height)
        // The atlas's size as rendered: whole pixels, so at a fractional
        // pixel ratio a little more than the bounds it was drawn in.
        ..content.set(
          barOrigin.dx,
          barOrigin.dy,
          atlas.width / _devicePixelRatio,
          atlas.height / _devicePixelRatio,
        )
        ..tabs.set(
          _physics.tabCenter(0),
          count > 1 ? _physics.tabCenter(1) - _physics.tabCenter(0) : 0,
          count.toDouble(),
          _atlasPitch,
        )
        ..platterTransform.set(
          platterCenter.dx,
          platterCenter.dy,
          drift.dx,
          drift.dy,
        )
        ..platterScale.set(
          _physics.platterScaleX,
          _physics.platterScaleY,
          size.height,
          _atlasSlot,
        )
        ..glow.set(
          glowPixels.dx,
          glowPixels.dy,
          1 / (2 * glowVariance),
          glowCenter == null ? 0 : glowAlpha * glowPeak,
        );
      u.shader.setImageSampler(1, atlas);
      return ui.ImageFilter.shader(u.shader);
    }

    // Pass 1, the bar: takes the capture, before any glass. Its shadows
    // reach past the platter.
    final bool shadows = _optics & GlassTabBarOptics.shadow != 0 && !diagnostic;
    _barClip.layer = context.pushClipRect(
      needsCompositing,
      offset,
      platter.inflate(shadows ? _shadowMargin : 2),
      (PaintingContext context, Offset offset) {
        final BackdropFilterLayer layer =
            (_barPass.layer ??= BackdropFilterLayer())
              ..filter = passFilter(0)
              ..backdropKey = _sharedCapture;
        context.pushLayer(layer, _paintNothing, offset);
      },
      oldLayer: _barClip.layer,
    );

    // The tabs outside the lens, under the press's wash.
    final double wash = _optics & GlassTabBarOptics.press != 0
        ? _washAmount * _physics.press
        : 0;
    void paintTabs(PaintingContext context, Offset offset) {
      context.pushTransform(
        needsCompositing,
        offset,
        _physics.platterTransform,
        (PaintingContext context, Offset offset) =>
            _paintTabs(context, offset, inside: false),
      );
    }

    if (wash > 0) {
      _washLayer.layer = context.pushColorFilter(
        offset,
        _washFilter(wash),
        paintTabs,
        oldLayer: _washLayer.layer,
      );
    } else {
      _washLayer.layer = null;
      paintTabs(context, offset);
    }

    // The fingertip glow, over the platter and its tabs: under the lens,
    // whose shader sees it through its optics.
    _paintGlow(context, offset, platter);

    // Pass 2, the lens: the same capture, with the tabs under it lifted into
    // it (drawn by its shader from the content atlas).
    final BackdropKey lensCapture = _shareBackdrop
        ? _sharedCapture
        : _lensOwnCapture;
    _lensClip.layer = context.pushClipRect(
      needsCompositing,
      offset,
      lens.inflate(shadows ? _lensShadowMargin : 2),
      (PaintingContext context, Offset offset) {
        final BackdropFilterLayer layer =
            (_lensPass.layer ??= BackdropFilterLayer())
              ..filter = passFilter(1)
              ..backdropKey = lensCapture;
        context.pushLayer(layer, _paintNothing, offset);
      },
      oldLayer: _lensClip.layer,
    );

    if (!diagnostic) {
      _inspectorClip.layer = null;
      _inspectorPass.layer = null;
      return;
    }

    // The inspector reads whatever the lens reads.
    _inspectorClip.layer = context.pushClipRect(
      needsCompositing,
      offset,
      inspector,
      (PaintingContext context, Offset offset) {
        final BackdropFilterLayer layer =
            (_inspectorPass.layer ??= BackdropFilterLayer())
              ..filter = passFilter(2)
              ..backdropKey = lensCapture;
        context.pushLayer(layer, (PaintingContext context, Offset offset) {
          _paintInspectorLabels(context.canvas, offset + inspector.topLeft);
        }, offset);
      },
      oldLayer: _inspectorClip.layer,
    );

    // The same field and finger in layout coordinates, as thin dark lines
    // down the middle of the shaders' colored ones.
    _paintLayoutCheck(context.canvas, offset);
  }

  static void _paintNothing(PaintingContext context, Offset offset) {}

  // How far the platter's shadow reaches past it: 39pt past its outline
  // moved 8pt down.
  static const double _shadowMargin = 48;

  // How far the lens's shadow reaches past it: its outline moved 7pt down,
  // and 9.2pt past that.
  static const double _lensShadowMargin = 18;

  // The press's wash (UIKit's white layer over the platter through a vibrant
  // color matrix): chroma x1.2 and a 0.05 lift, at 0.8448 when pressed. The
  // glass shaders apply it to the platter and the lens; this filter, to the
  // tabs over them.
  static const double _washAmount = 0.8448;
  final LayerHandle<ColorFilterLayer> _washLayer =
      LayerHandle<ColorFilterLayer>();

  static ColorFilter _washFilter(double w) {
    const double r = 0.2126, g = 0.7152, b = 0.0722;
    final double k = 1 + 0.2 * w, m = -0.2 * w, lift = 0.05 * w * 255;
    return ColorFilter.matrix(<double>[
      k + m * r, m * g, m * b, 0, lift, //
      m * r, k + m * g, m * b, 0, lift,
      m * r, m * g, k + m * b, 0, lift,
      0, 0, 0, 1, 0,
    ]);
  }

  // UIKit's LittleGlowView: a white disk under the finger, blurred, clipped
  // to the platter.
  void _paintGlow(PaintingContext context, Offset offset, Rect platter) {
    final Offset? center = _physics.glowCenter;
    final double alpha = _physics.glowAlpha;
    if (_optics & GlassTabBarOptics.press == 0 ||
        center == null ||
        alpha < 1 / 512) {
      _glowClip.layer = null;
      return;
    }
    _glowClip.layer = context.pushClipRRect(
      needsCompositing,
      offset,
      platter,
      RRect.fromRectAndRadius(
        platter,
        Radius.circular(platter.shortestSide / 2),
      ),
      (PaintingContext context, Offset offset) {
        context.canvas.drawCircle(
          offset + center,
          _physics.glowSize / 2,
          Paint()
            ..color = Color.fromRGBO(255, 255, 255, alpha)
            ..maskFilter = MaskFilter.blur(
              BlurStyle.normal,
              _physics.glowSigma,
            ),
        );
      },
      oldLayer: _glowClip.layer,
    );
  }

  final LayerHandle<ClipRRectLayer> _glowClip = LayerHandle<ClipRRectLayer>();

  // UIKit's gradientOvalization for the glass's distance field.
  static const double _ovalization = 0.5;
  static const double _inspectorZoom = 2;

  Rect get _inspectorRect =>
      _inspector ?? Rect.fromLTWH(0, -24 - 300, size.width, 300);

  void _paintInspectorLabels(Canvas canvas, Offset origin) {
    final painter = TextPainter(
      text: TextSpan(
        text:
            '${_shareBackdrop ? 'shared capture' : "lens's own capture, taken after the bar's glass"}'
            ', ×2: yellow bar, cyan lens, '
            'pink sampling region, orange sampled band',
        style: const TextStyle(fontSize: 10, color: Color(0xFFFFFFFF)),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: _inspectorRect.width - 12);
    canvas.drawRect(
      Rect.fromLTWH(
        origin.dx,
        origin.dy,
        painter.width + 12,
        painter.height + 8,
      ),
      Paint()..color = const Color(0xB0000000),
    );
    painter.paint(canvas, origin + const Offset(6, 4));
    painter.dispose();
  }

  void _paintLayoutCheck(Canvas canvas, Offset offset) {
    final double hair = 1 / _devicePixelRatio;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = hair
      ..color = const Color(0xFF000000);
    for (final Rect r in <Rect>[_physics.platterRect, _physics.lensRect]) {
      final Rect inset = r.deflate(0.75).shift(offset);
      canvas.drawRRect(
        RRect.fromRectAndRadius(inset, Radius.circular(inset.shortestSide / 2)),
        line,
      );
    }
    final Offset? touch = _physics.touch;
    if (touch != null) {
      final Offset t = touch + offset;
      canvas
        ..drawLine(t - const Offset(10, 0), t + const Offset(10, 0), line)
        ..drawLine(t - const Offset(0, 10), t + const Offset(0, 10), line);
    }
  }

  // -------------------------------------------------------- the lifted content

  // The selected-style tabs, one per slot of an image, for the lens's shader
  // to grow and lens each about its own center (as UIKit scales its
  // selected tab buttons and lenses them through the lens). Rendered again
  // only when the tabs or their layout change, not every animation frame.
  ui.Image? _contentAtlas;
  ui.Image? _noContent;
  bool _contentDirty = true;

  // Room around each tab for labels wider than the pill.
  static const double _atlasMargin = 12;
  double get _atlasSlot => _physics.pillWidth + 2 * _atlasMargin;
  double get _atlasPitch => _atlasSlot + 2;

  ui.Image _ensureContentAtlas() {
    final int count = _tabCount;
    if (count == 0 || size.isEmpty) {
      return _noContent ??= _emptyImage();
    }
    if (_contentDirty || _contentAtlas == null) {
      _contentDirty = false;
      final Rect bounds = Rect.fromLTWH(0, 0, count * _atlasPitch, size.height);
      final layer = OffsetLayer();
      final context = _AtlasContext(layer, bounds);
      var i = 0;
      RenderBox? child = firstChild;
      while (child != null) {
        if (i >= count) {
          context.paintChild(
            child,
            Offset((i - count) * _atlasPitch + _atlasMargin, 0),
          );
        }
        child = childAfter(child);
        i++;
      }
      context.finish();
      _contentAtlas?.dispose();
      _contentAtlas = layer.toImageSync(bounds, pixelRatio: _devicePixelRatio);
      layer.dispose();
    }
    return _contentAtlas!;
  }

  static ui.Image _emptyImage() {
    final recorder = ui.PictureRecorder();
    Canvas(recorder);
    final ui.Picture picture = recorder.endRecording();
    final ui.Image image = picture.toImageSync(1, 1);
    picture.dispose();
    return image;
  }

  // ------------------------------------------------------------ the tab items

  // The tabs, inside the platter: normal outside the lens, in the selected
  // color within it.
  void _paintTabs(PaintingContext context, Offset offset, {bool? inside}) {
    final Rect lens = _physics.lensInPlatter.shift(offset);
    final RRect lensShape = RRect.fromRectAndRadius(
      lens,
      Radius.circular(lens.shortestSide / 2),
    );
    final Rect bounds = (offset & size).inflate(40);
    final int count = _tabCount;
    if (inside != true) {
      final outside = Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(bounds)
        ..addRRect(lensShape);
      context.canvas
        ..save()
        ..clipPath(outside);
      _paintChildren(context, offset, 0, count);
      context.canvas.restore();
    }
    if (inside != false) {
      context.canvas
        ..save()
        ..clipRRect(lensShape);
      _paintChildren(context, offset, count, 2 * count);
      context.canvas.restore();
    }
  }

  void _paintChildren(
    PaintingContext context,
    Offset offset,
    int from,
    int to,
  ) {
    var i = 0;
    RenderBox? child = firstChild;
    while (child != null) {
      if (i >= from && i < to) {
        context.paintChild(
          child,
          (child.parentData! as _TabParentData).offset + offset,
        );
      }
      child = childAfter(child);
      i++;
    }
  }

  // ------------------------------------------------ the field, drawn flat

  void _paintField(Canvas canvas, Offset offset) {
    final Rect platter = _physics.platterRect.shift(offset);
    final Rect lens = _physics.lensRect.shift(offset);
    final ui.FragmentProgram? program = GlassTabBar._field.program;
    if (program == null) {
      // Until the shader is in: the same shapes, drawn plainly.
      canvas
        ..drawRRect(
          RRect.fromRectAndRadius(
            platter,
            Radius.circular(platter.shortestSide / 2),
          ),
          Paint()..color = const Color(0xFFD6D6D6),
        )
        ..drawRRect(
          RRect.fromRectAndRadius(lens, Radius.circular(lens.shortestSide / 2)),
          Paint()..color = const Color(0xFFBDBDBD),
        );
      return;
    }
    final ui.FragmentShader shader = _fieldShader ??= program.fragmentShader();
    shader
      ..getUniformVec4('uPlatter').set(
        platter.center.dx,
        platter.center.dy,
        platter.width / 2,
        platter.height / 2,
      )
      ..getUniformVec4(
        'uLens',
      ).set(lens.center.dx, lens.center.dy, lens.width / 2, lens.height / 2)
      ..getUniformVec4('uState').set(
        _physics.clear,
        0.5,
        1 / _devicePixelRatio,
        _debugView == GlassTabBarDebugView.normals ? 1 : 0,
      );
    canvas.drawRect(
      platter.expandToInclude(lens).inflate(2),
      Paint()..shader = shader,
    );
  }
}

/// Maps the bar's layout coordinates to the capture's: physical pixels of
/// the pass the backdrop is captured from (the root pass, unless an
/// ancestor draws into its own layer).
class _CaptureSpace {
  _CaptureSpace(this.toRoot, this.devicePixelRatio)
    : pointSize =
          devicePixelRatio *
          (MatrixUtils.transformPoint(toRoot, const Offset(1, 0)) -
                  MatrixUtils.transformPoint(toRoot, Offset.zero))
              .distance;

  final Matrix4 toRoot;
  final double devicePixelRatio;

  /// One layout point, in capture pixels.
  final double pointSize;

  Offset point(Offset p) =>
      MatrixUtils.transformPoint(toRoot, p) * devicePixelRatio;

  Rect rect(Rect r) {
    final Rect g = MatrixUtils.transformRect(toRoot, r);
    return Rect.fromLTRB(
      g.left * devicePixelRatio,
      g.top * devicePixelRatio,
      g.right * devicePixelRatio,
      g.bottom * devicePixelRatio,
    );
  }
}

/// Named bindings into the backdrop shader.
class _BackdropUniforms {
  _BackdropUniforms(this.shader)
    : pass = shader.getUniformVec4('uPass'),
      platter = shader.getUniformVec4('uPlatter'),
      lens = shader.getUniformVec4('uLens'),
      optics = shader.getUniformVec4('uOptics'),
      touch = shader.getUniformVec4('uTouch'),
      inspector = shader.getUniformVec4('uInspector'),
      window = shader.getUniformVec4('uWindow'),
      content = shader.getUniformVec4('uContent'),
      tabs = shader.getUniformVec4('uTabs'),
      platterTransform = shader.getUniformVec4('uPlatterXf'),
      platterScale = shader.getUniformVec4('uPlatterS'),
      glow = shader.getUniformVec4('uGlow');

  final ui.FragmentShader shader;
  final ui.UniformVec4Slot pass;
  final ui.UniformVec4Slot platter;
  final ui.UniformVec4Slot lens;
  final ui.UniformVec4Slot optics;
  final ui.UniformVec4Slot touch;
  final ui.UniformVec4Slot inspector;
  final ui.UniformVec4Slot window;
  final ui.UniformVec4Slot content;
  final ui.UniformVec4Slot tabs;
  final ui.UniformVec4Slot platterTransform;
  final ui.UniformVec4Slot platterScale;
  final ui.UniformVec4Slot glow;
}

/// Paints the tabs into a layer of their own, for the content atlas.
class _AtlasContext extends PaintingContext {
  _AtlasContext(super.containerLayer, super.estimatedBounds);

  void finish() => stopRecordingIfNeeded();
}

extension on ui.UniformVec4Slot {
  // A rect as its center and half size.
  void setRect(Rect r) =>
      set(r.center.dx, r.center.dy, r.width / 2, r.height / 2);
}
