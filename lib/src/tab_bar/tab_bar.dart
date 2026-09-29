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
  /// The glass field flat: platter, pill and lens silhouettes.
  field,

  /// The lens's surface normals as colors.
  normals,
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
    this.debugView = GlassTabBarDebugView.field,
  });

  /// Height of the bar, as on iOS 26.
  static const double height = 62;

  final List<GlassTabItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final GlassTabBarDebugView debugView;

  static final ShaderProgram _field = ShaderProgram('field.frag');

  /// Loads the bar's shaders ahead of time, so the first frame has them.
  static Future<void> precache() => _field.load();

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
    GlassTabBar._field.load().then((_) {
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
    required this.devicePixelRatio,
    required super.children,
  });

  final GlassTabBarPhysics physics;
  final Listenable frame;
  final ValueChanged<PointerEvent> onPointer;
  final GlassTabBarDebugView debugView;
  final double devicePixelRatio;

  @override
  RenderGlassTabBar createRenderObject(BuildContext context) {
    return RenderGlassTabBar(
      physics: physics,
      frame: frame,
      onPointer: onPointer,
      debugView: debugView,
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
      ..devicePixelRatio = devicePixelRatio;
  }
}

class _TabParentData extends ContainerBoxParentData<RenderBox> {}

/// Lays out a [GlassTabBar]'s tabs (each twice: normal, then in the
/// selected color), takes its touches, and paints the glass and the tabs
/// where [GlassTabBarPhysics] puts them.
class RenderGlassTabBar extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _TabParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _TabParentData> {
  RenderGlassTabBar({
    required this._physics,
    required this._frame,
    required this.onPointer,
    required this._debugView,
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

  ui.FragmentShader? _shader;

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
    _shader?.dispose();
    super.dispose();
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
  bool get alwaysNeedsCompositing => false;

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_tabCount == 0) {
      return;
    }
    _paintField(context.canvas, offset);
    context.pushTransform(
      needsCompositing,
      offset,
      _physics.platterTransform,
      _paintTabs,
    );
  }

  // The tabs, inside the platter: normal outside the lens, in the selected
  // color within it.
  void _paintTabs(PaintingContext context, Offset offset) {
    final Rect lens = _physics.lensInPlatter.shift(offset);
    final RRect lensShape = RRect.fromRectAndRadius(
      lens,
      Radius.circular(lens.shortestSide / 2),
    );
    final Rect bounds = (offset & size).inflate(40);
    final int count = _tabCount;

    final outside = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(bounds)
      ..addRRect(lensShape);
    context.canvas
      ..save()
      ..clipPath(outside);
    _paintChildren(context, offset, 0, count);
    context.canvas
      ..restore()
      ..save()
      ..clipRRect(lensShape);
    _paintChildren(context, offset, count, 2 * count);
    context.canvas.restore();
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
    final ui.FragmentShader shader = _shader ??= program.fragmentShader();
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
