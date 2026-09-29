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
    return SizedBox(
      height: GlassTabBar.height,
      child: _TabBarLayout(
        physics: _physics,
        frame: _frame,
        onPointer: _handlePointer,
        debugView: widget.debugView,
        shareBackdrop: widget.debugShareBackdrop,
        inspector: widget.debugInspector,
        devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
        children: <Widget>[
          for (var i = 0; i < items.length; i++)
            Semantics(
              button: true,
              selected: i == widget.selectedIndex,
              label: items[i].label,
              onTap: () => widget.onSelected(i),
              child: ExcludeSemantics(
                child: _TabView(item: items[i], color: _normal),
              ),
            ),
          for (var i = 0; i < items.length; i++)
            ExcludeSemantics(
              child: _TabView(item: items[i], color: _selected),
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
    required this.devicePixelRatio,
    required super.children,
  });

  final GlassTabBarPhysics physics;
  final Listenable frame;
  final ValueChanged<PointerEvent> onPointer;
  final GlassTabBarDebugView debugView;
  final bool shareBackdrop;
  final Rect? inspector;
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
/// never sees the bar's glass, the tabs, or itself.
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
    _frame.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _frame.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void dispose() {
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
  }

  int get _tabCount => childCount ~/ 2;

  @override
  void performLayout() {
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
          _physics.liftProgress,
          _refractionAtRim * space.pointSize,
          _refractionBevel * space.pointSize,
          0,
        )
        ..touch.set(finger.dx, finger.dy, touch == null ? 0 : 1, 0)
        ..inspector.set(
          inspectorPixels.left,
          inspectorPixels.top,
          inspectorPixels.width,
          inspectorPixels.height,
        )
        ..window.set(window.left, window.top, window.width, window.height);
      return ui.ImageFilter.shader(u.shader);
    }

    // Pass 1, the bar: takes the capture, before any glass.
    _barClip.layer = context.pushClipRect(
      needsCompositing,
      offset,
      platter.inflate(2),
      (PaintingContext context, Offset offset) {
        final BackdropFilterLayer layer =
            (_barPass.layer ??= BackdropFilterLayer())
              ..filter = passFilter(0)
              ..backdropKey = _sharedCapture;
        context.pushLayer(layer, _paintNothing, offset);
      },
      oldLayer: _barClip.layer,
    );

    // The tabs outside the lens.
    context.pushTransform(
      needsCompositing,
      offset,
      _physics.platterTransform,
      (PaintingContext context, Offset offset) =>
          _paintTabs(context, offset, inside: false),
    );

    // Pass 2, the lens: the same capture, and the tabs under it on top.
    final BackdropKey lensCapture = _shareBackdrop
        ? _sharedCapture
        : _lensOwnCapture;
    _lensClip.layer = context.pushClipRect(
      needsCompositing,
      offset,
      lens.inflate(2),
      (PaintingContext context, Offset offset) {
        final BackdropFilterLayer layer =
            (_lensPass.layer ??= BackdropFilterLayer())
              ..filter = passFilter(1)
              ..backdropKey = lensCapture;
        context.pushLayer(layer, (PaintingContext context, Offset offset) {
          context.pushTransform(
            needsCompositing,
            offset,
            _physics.platterTransform,
            (PaintingContext context, Offset offset) =>
                _paintTabs(context, offset, inside: true),
          );
        }, offset);
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

  // How far the lens reaches past its rim and over how deep a bevel, in
  // points: UIKit's lifted lens displacement (9) and its SDF glass effect
  // height (11.2). Placeholders until the optics are fitted.
  static const double _refractionAtRim = 9;
  static const double _refractionBevel = 11.2;
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
      window = shader.getUniformVec4('uWindow');

  final ui.FragmentShader shader;
  final ui.UniformVec4Slot pass;
  final ui.UniformVec4Slot platter;
  final ui.UniformVec4Slot lens;
  final ui.UniformVec4Slot optics;
  final ui.UniformVec4Slot touch;
  final ui.UniformVec4Slot inspector;
  final ui.UniformVec4Slot window;
}

extension on ui.UniformVec4Slot {
  // A rect as its center and half size.
  void setRect(Rect r) =>
      set(r.center.dx, r.center.dy, r.width / 2, r.height / 2);
}
