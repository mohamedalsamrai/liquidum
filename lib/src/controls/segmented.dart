import 'dart:math' as math;

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../lens/lens.dart';
import '../tab_bar/spring.dart';
import 'lens_seam.dart';
import 'motion.dart';

/// UIKit's segmented control (`UISegmentedControl`, iOS 26): segments of
/// equal width in a 32pt capsule, the selected one under a pill that is
/// the liquid lens.
///
/// ```dart
/// GlassSegmentedControl<String>(
///   children: {'One': Text('One'), 'Two': Text('Two')},
///   groupValue: choice,
///   onValueChanged: (String v) => setState(() => choice = v),
/// )
/// ```
///
/// A touch on another segment selects it as the finger leaves, and the
/// selection slides there. Pressing the selected segment lifts its pill
/// into the lens; dragged, it follows the finger and settles on the
/// segment it is let go over, which becomes selected. With no
/// [onValueChanged] the control is disabled: dimmed, and still. It is as
/// wide as its widest segment times their number, or as wide as it is
/// made.
class GlassSegmentedControl<T extends Object> extends StatefulWidget {
  const GlassSegmentedControl({
    super.key,
    required this.children,
    required this.groupValue,
    required this.onValueChanged,
    this.tint,
  }) : assert(children.length >= 2, 'At least two segments.');

  /// The segments, in order: a value and what shows for it (text takes
  /// UIKit's label style).
  final Map<T, Widget> children;

  /// The selected segment's value (none selected when null, or not among
  /// [children]).
  final T? groupValue;

  /// Called with the value of the segment chosen; null disables the
  /// control.
  final ValueChanged<T>? onValueChanged;

  /// The selected segment's pill color (UIKit's `selectedSegmentTintColor`):
  /// white by default, a translucent gray in the dark appearance.
  final Color? tint;

  @override
  State<GlassSegmentedControl<T>> createState() =>
      _GlassSegmentedControlState<T>();
}

/// UIKit's numbers for the segmented control (iOS 26.5, measured on its
/// layers and frame by frame; see doc/comparison/glass-widgets/stage4).
abstract final class _SegmentMetrics {
  static const double height = 32;

  /// The selection's inset from the control's edge, and from the segment's
  /// sides.
  static const double inset = 2;

  /// How far the lifted pill grows past the resting one, per side, across
  /// and down.
  static const Offset liftOutset = Offset(12, 8);

  /// Space either side of a segment's label, when the control sizes to its
  /// content.
  static const double padding = 10;

  /// Labels: 13pt, medium when selected. UIKit draws SF's G3 grade, whose
  /// glyphs come out 3.5% larger than Flutter's 13pt (cap height and
  /// width).
  static const double fontSize = 13.45;
  static const FontWeight selectedWeight = FontWeight.w500;
  static const FontWeight weight = FontWeight.w400;

  // Colors: the track (115, 115, 123 at 0.12 light; 117, 117, 130 at 0.24
  // dark), the selection (white; a translucent light gray in dark, 193,
  // 193, 204 at 0.47), the labels black and white.
  static const Color trackLight = Color(0x1F73737B);
  static const Color trackDark = Color(0x3D757582);
  static const Color selectionLight = Color(0xFFFFFFFF);
  static const Color selectionDark = Color(0x78C1C1CC);
  static const Color labelLight = Color(0xFF000000);
  static const Color labelDark = Color(0xFFFFFFFF);

  /// Disabled: everything at half its alpha.
  static const double disabledOpacity = 0.5;

  /// The selection's slide to a tapped segment (stiffness, damping): 3%
  /// over, 0.41s.
  static const (double, double) slide = (235, 26);

  /// Its snap to the segment a drag ends over: critically damped, 0.25s.
  static const (double, double) snap = (613, 48.7);

  /// The selection's lens: UIKit's large liquid lens (the tab bar's, by
  /// its lifted height), lifting and falling on the large spring, with no
  /// hang.
  static const LensVariant lensVariant = LensVariant.large;
  static const LensOptics optics = LensOptics.large(height - 2 * inset + 16);
}

class _GlassSegmentedControlState<T extends Object>
    extends State<GlassSegmentedControl<T>>
    with SingleTickerProviderStateMixin {
  final GlassSpring _selection = GlassSpring(
    response: physicalSpring(
      _SegmentMetrics.slide.$1,
      _SegmentMetrics.slide.$2,
    ).$1,
    dampingRatio: physicalSpring(
      _SegmentMetrics.slide.$1,
      _SegmentMetrics.slide.$2,
    ).$2,
    tolerance: 1e-3,
  );
  final LensLift _lift = LensLift(
    variant: _SegmentMetrics.lensVariant,
    hangTime: 0,
  );
  final LensFlex _flex = LensFlex.forWidth(100);
  late final ControlMotion _motion = ControlMotion(
    this,
    <GlassSpring>[_selection],
    lift: _lift,
    flex: _flex,
    position: () => _selection.value * _segmentWidth + _flex.drift,
  );
  final GlobalKey _boxKey = GlobalKey();

  bool _rtl = false;
  bool _armed = false;
  bool _dragging = false;
  double _dragFrom = 0;
  double _dragX = 0;
  double? _pointerX;

  bool get _enabled => widget.onValueChanged != null;
  List<T> get _values => widget.children.keys.toList();
  int get _count => widget.children.length;

  /// The selected segment's index, or -1.
  int get _selectedIndex {
    final T? value = widget.groupValue;
    return value == null ? -1 : _values.indexOf(value);
  }

  @override
  void initState() {
    super.initState();
    _selection.snap(math.max(_selectedIndex, 0).toDouble());
  }

  @override
  void didUpdateWidget(GlassSegmentedControl<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_dragging && _selectedIndex >= 0) {
      _selection.target = _selectedIndex.toDouble();
      _motion.wake();
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    _lift.dispose();
    super.dispose();
  }

  // A segment's width (points), from the last layout.
  double get _segmentWidth {
    final RenderObject? box = _boxKey.currentContext?.findRenderObject();
    return box is _RenderSegmentedBox ? box.segmentWidth : 0;
  }

  // The segment under x, in the control's coordinates.
  int _indexAt(double x) {
    final double w = _segmentWidth;
    if (w <= 0) {
      return -1;
    }
    final int i = (x / w).floor().clamp(0, _count - 1);
    return _rtl ? _count - 1 - i : i;
  }

  // Selects segment [index] and slides the selection there on [spring].
  void _choose(int index, (double, double) spring) {
    if (index < 0) {
      return;
    }
    final (double r, double z) = physicalSpring(spring.$1, spring.$2);
    _selection.configure(r, z);
    if (index != _selectedIndex) {
      widget.onValueChanged?.call(_values[index]);
    }
    _selection.target = index.toDouble();
    _motion.wake();
    // If the owner keeps its value, the selection comes back once the
    // frame has shown it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_dragging && _selectedIndex >= 0) {
        _selection.target = _selectedIndex.toDouble();
        _motion.wake();
      }
    });
  }

  void _tapUp(TapUpDetails details) =>
      _choose(_indexAt(details.localPosition.dx), _SegmentMetrics.slide);

  void _down(DragDownDetails details) {
    _pointerX = details.localPosition.dx;
    // Only the selected segment lifts and drags; a touch elsewhere selects
    // the segment it ends over.
    _armed =
        _selectedIndex >= 0 &&
        _indexAt(details.localPosition.dx) == _selectedIndex;
    if (_armed) {
      _flex.driftPerState = LensFlex.driftPerWidth * _pillWidth;
      _lift.down();
      _motion.wake();
    }
  }

  void _start(DragStartDetails details) {
    _pointerX = details.localPosition.dx;
    if (!_armed) {
      return;
    }
    _dragging = true;
    _dragFrom = _selection.value;
    _dragX = details.localPosition.dx;
  }

  void _update(DragUpdateDetails details) {
    _pointerX = details.localPosition.dx;
    if (!_dragging || _segmentWidth <= 0) {
      return;
    }
    final double dx = (details.localPosition.dx - _dragX) * (_rtl ? -1 : 1);
    final int before = _selection.value.round();
    _selection.snap(
      (_dragFrom + dx / _segmentWidth).clamp(0.0, (_count - 1).toDouble()),
    );
    if (_selection.value.round() != before) {
      // The label under the lens turns medium.
      setState(() {});
    }
    _motion.wake();
  }

  void _end(DragEndDetails details) {
    final double? x = _pointerX;
    if (_dragging) {
      setState(() => _dragging = false);
      // The segment under the finger: the lens's snap.
      _choose(
        x == null ? _selection.value.round() : _indexAt(x),
        _SegmentMetrics.snap,
      );
    } else if (x != null) {
      // A touch that started elsewhere: the segment it ends over.
      _choose(_indexAt(x), _SegmentMetrics.slide);
    }
    _release();
  }

  void _cancel() {
    if (_dragging) {
      setState(() => _dragging = false);
      _selection.target = math.max(_selectedIndex, 0).toDouble();
      _motion.wake();
    }
    _release();
  }

  // The finger left: the lens falls back.
  void _release() {
    if (_armed) {
      _armed = false;
      _lift.up();
      _motion.wake();
    }
  }

  // The resting pill's width (points): a segment inset.
  double get _pillWidth =>
      math.max(_segmentWidth - 2 * _SegmentMetrics.inset, 1);

  @override
  Widget build(BuildContext context) {
    final bool dark =
        MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    final bool still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _lift.reduceMotion = still;
    _motion.reduceMotion = still;
    final TextDirection direction =
        Directionality.maybeOf(context) ?? TextDirection.ltr;
    _rtl = direction == TextDirection.rtl;
    final double opacity = _enabled ? 1 : _SegmentMetrics.disabledOpacity;
    final Color label = dimmed(
      dark ? _SegmentMetrics.labelDark : _SegmentMetrics.labelLight,
      opacity,
    );
    // The label in medium: the selected segment's, and while the selection
    // is dragged the segment under it (UIKit's label switches as the lens
    // passes, before the value changes on release).
    final int selected = _dragging && _count > 0
        ? _selection.value.round().clamp(0, _count - 1)
        : _selectedIndex;
    final List<Widget> labels = <Widget>[
      for (final (int i, MapEntry<T, Widget> e)
          in widget.children.entries.indexed)
        Semantics(
          button: true,
          selected: i == selected,
          inMutuallyExclusiveGroup: true,
          enabled: _enabled,
          onTap: _enabled ? () => _choose(i, _SegmentMetrics.slide) : null,
          child: DefaultTextStyle.merge(
            style: TextStyle(
              fontSize: _SegmentMetrics.fontSize,
              fontWeight: i == selected
                  ? _SegmentMetrics.selectedWeight
                  : _SegmentMetrics.weight,
              color: label,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            child: IconTheme.merge(
              data: IconThemeData(color: label, size: 17),
              child: e.value,
            ),
          ),
        ),
    ];
    return Semantics(
      container: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Drags count from the touch, not from where they were told
        // apart from a tap.
        dragStartBehavior: DragStartBehavior.down,
        onTapUp: _enabled ? _tapUp : null,
        onHorizontalDragDown: _enabled ? _down : null,
        onHorizontalDragStart: _enabled ? _start : null,
        onHorizontalDragUpdate: _enabled ? _update : null,
        onHorizontalDragEnd: _enabled ? _end : null,
        onHorizontalDragCancel: _enabled ? _cancel : null,
        child: ListenableBuilder(
          listenable: _motion,
          builder: (BuildContext context, _) => _SegmentedBox(
            key: _boxKey,
            count: _count,
            selection: selected < 0 && !_dragging ? null : _selection.value,
            // The pill grows toward its lifted size with the lens's bounds
            // (overshooting as they do).
            growth: math.max(_lift.growth, -0.25),
            lift: _lift.lift,
            textDirection: direction,
            trackColor: dimmed(
              dark ? _SegmentMetrics.trackDark : _SegmentMetrics.trackLight,
              opacity,
            ),
            // The box paints the track (cut out under the lifted lens, as
            // UIKit's is, so the lens refracts the page behind), then the
            // lens over it, then the labels over the lens, as UIKit draws
            // them. It places the lens (its segments' width is only known
            // in its layout).
            lens: ControlLens(
              rect: null,
              lift: _lift.lift,
              optics: _SegmentMetrics.optics,
              flexScale: _flex.scale,
              drift: Offset(_flex.drift, 0),
              opacity: opacity,
              color:
                  widget.tint ??
                  (dark
                      ? _SegmentMetrics.selectionDark
                      : _SegmentMetrics.selectionLight),
            ),
            labels: _SegmentLabels(
              count: _count,
              textDirection: direction,
              children: labels,
            ),
          ),
        ),
      ),
    );
  }
}

// Segment i's left edge (i continuous), in a control [count] segments wide.
double _segmentLeft(
  double i,
  int count,
  double segmentWidth,
  TextDirection direction,
) => direction == TextDirection.rtl
    ? (count - 1 - i) * segmentWidth
    : i * segmentWidth;

/// The control's box: sizes to its [labels], paints the track (in
/// [trackColor], cut out under the lens by [lift]), places the [lens] at
/// [selection], grown by [growth], over it, and paints the labels over the
/// lens.
class _SegmentedBox extends MultiChildRenderObjectWidget {
  _SegmentedBox({
    super.key,
    required this.count,
    required this.selection,
    required this.growth,
    required this.lift,
    required this.textDirection,
    required this.trackColor,
    required Widget lens,
    required Widget labels,
  }) : super(children: <Widget>[lens, labels]);

  final int count;

  /// The selection's place, in segments (continuous); none when null.
  final double? selection;
  final double growth;
  final double lift;
  final TextDirection textDirection;
  final Color trackColor;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderSegmentedBox(
    count: count,
    selection: selection,
    growth: growth,
    lift: lift,
    textDirection: textDirection,
    trackColor: trackColor,
  );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSegmentedBox renderObject,
  ) {
    renderObject
      ..count = count
      ..selection = selection
      ..growth = growth
      ..lift = lift
      ..textDirection = textDirection
      ..trackColor = trackColor;
  }
}

class _RenderSegmentedBox extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _SegmentParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _SegmentParentData> {
  _RenderSegmentedBox({
    required int count,
    required double? selection,
    required double growth,
    required double lift,
    required TextDirection textDirection,
    required Color trackColor,
  }) : this._(count, selection, growth, lift, textDirection, trackColor);

  _RenderSegmentedBox._(
    this._count,
    this._selection,
    this._growth,
    this._lift,
    this._textDirection,
    this._trackColor,
  );

  double _lift;
  set lift(double value) {
    if (value != _lift) {
      _lift = value;
      markNeedsPaint();
    }
  }

  Color _trackColor;
  set trackColor(Color value) {
    if (value != _trackColor) {
      _trackColor = value;
      markNeedsPaint();
    }
  }

  int _count;
  set count(int value) {
    if (value != _count) {
      _count = value;
      markNeedsLayout();
    }
  }

  double? _selection;
  set selection(double? value) {
    if (value != _selection) {
      _selection = value;
      markNeedsLayout();
    }
  }

  double _growth;
  set growth(double value) {
    if (value != _growth) {
      _growth = value;
      markNeedsLayout();
    }
  }

  TextDirection _textDirection;
  set textDirection(TextDirection value) {
    if (value != _textDirection) {
      _textDirection = value;
      markNeedsLayout();
    }
  }

  /// A segment's width, from the last layout.
  double get segmentWidth => hasSize ? size.width / _count : 0;

  RenderBox? get _lens => firstChild;
  RenderBox? get _labels => lastChild;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _SegmentParentData) {
      child.parentData = _SegmentParentData();
    }
  }

  double _contentWidth(double height) =>
      _labels?.getMaxIntrinsicWidth(height) ?? 0;

  @override
  double computeMinIntrinsicWidth(double height) => _contentWidth(height);

  @override
  double computeMaxIntrinsicWidth(double height) => _contentWidth(height);

  @override
  double computeMinIntrinsicHeight(double width) => _SegmentMetrics.height;

  @override
  double computeMaxIntrinsicHeight(double width) => _SegmentMetrics.height;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.constrain(
    Size(_contentWidth(_SegmentMetrics.height), _SegmentMetrics.height),
  );

  // The selection's pill: its segment inset, grown by the lift about its
  // center (12pt a side across, 8 down, when lifted).
  Rect _selectionRect() {
    final double? s = _selection;
    if (s == null) {
      return Rect.zero;
    }
    final double w = segmentWidth;
    final Rect rest = Rect.fromLTWH(
      _segmentLeft(s, _count, w, _textDirection) + _SegmentMetrics.inset,
      _SegmentMetrics.inset,
      w - 2 * _SegmentMetrics.inset,
      size.height - 2 * _SegmentMetrics.inset,
    );
    return Rect.fromCenter(
      center: rest.center,
      width: rest.width + 2 * _SegmentMetrics.liftOutset.dx * _growth,
      height: rest.height + 2 * _SegmentMetrics.liftOutset.dy * _growth,
    );
  }

  @override
  void performLayout() {
    size = computeDryLayout(constraints);
    final RenderBox? lens = _lens;
    if (lens is RenderLiquidLens) {
      lens.rect = _selectionRect();
    }
    RenderBox? child = firstChild;
    while (child != null) {
      child.layout(BoxConstraints.tight(size));
      (child.parentData! as _SegmentParentData).offset = Offset.zero;
      child = childAfter(child);
    }
  }

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);

  @override
  void paint(PaintingContext context, Offset offset) {
    // The track, with the lens's pill cut out of it as the lens lifts
    // (UIKit's destOut view): the lifted lens refracts what is behind the
    // control, not the track.
    final Canvas canvas = context.canvas;
    final RRect track = RRect.fromRectAndRadius(
      offset & size,
      Radius.circular(size.height / 2),
    );
    final double cut = _lift.clamp(0.0, 1.0);
    final RenderBox? lens = _lens;
    if (cut > 0 && lens is RenderLiquidLens) {
      final Rect hole = lens.drawnRect.shift(offset);
      canvas
        ..saveLayer(track.outerRect, Paint())
        ..drawRRect(track, Paint()..color = _trackColor)
        ..drawRRect(
          RRect.fromRectAndRadius(hole, Radius.circular(hole.shortestSide / 2)),
          Paint()
            ..blendMode = BlendMode.dstOut
            ..color = Color.fromRGBO(0, 0, 0, cut),
        )
        ..restore();
    } else {
      canvas.drawRRect(track, Paint()..color = _trackColor);
    }
    defaultPaint(context, offset);
  }
}

/// The labels, in segments of equal width, over the lens (UIKit draws a
/// segmented control's labels above its selection).
class _SegmentLabels extends MultiChildRenderObjectWidget {
  const _SegmentLabels({
    required this.count,
    required this.textDirection,
    required super.children,
  });

  final int count;
  final TextDirection textDirection;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSegmentLabels(count: count, textDirection: textDirection);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSegmentLabels renderObject,
  ) {
    renderObject
      ..count = count
      ..textDirection = textDirection;
  }
}

class _SegmentParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderSegmentLabels extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _SegmentParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _SegmentParentData> {
  _RenderSegmentLabels({
    required int count,
    required TextDirection textDirection,
  }) : this._(count, textDirection);

  _RenderSegmentLabels._(this._count, this._textDirection);

  int _count;
  set count(int value) {
    if (value != _count) {
      _count = value;
      markNeedsLayout();
    }
  }

  TextDirection _textDirection;
  set textDirection(TextDirection value) {
    if (value != _textDirection) {
      _textDirection = value;
      markNeedsLayout();
    }
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _SegmentParentData) {
      child.parentData = _SegmentParentData();
    }
  }

  Iterable<RenderBox> get _labels sync* {
    RenderBox? child = firstChild;
    while (child != null) {
      yield child;
      child = childAfter(child);
    }
  }

  // The widest label with its padding (points).
  double get _contentWidth {
    var w = 0.0;
    for (final RenderBox label in _labels) {
      w = math.max(
        w,
        label.getMaxIntrinsicWidth(_SegmentMetrics.height) +
            2 * _SegmentMetrics.padding,
      );
    }
    return w;
  }

  @override
  double computeMinIntrinsicWidth(double height) => _contentWidth * _count;

  @override
  double computeMaxIntrinsicWidth(double height) => _contentWidth * _count;

  @override
  double computeMinIntrinsicHeight(double width) => _SegmentMetrics.height;

  @override
  double computeMaxIntrinsicHeight(double width) => _SegmentMetrics.height;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.constrain(
    Size(_contentWidth * _count, _SegmentMetrics.height),
  );

  @override
  void performLayout() {
    size = computeDryLayout(constraints);
    final double w = size.width / _count;
    var i = 0;
    for (final RenderBox label in _labels) {
      label.layout(
        BoxConstraints(maxWidth: w, maxHeight: size.height),
        parentUsesSize: true,
      );
      (label.parentData! as _SegmentParentData).offset = Offset(
        _segmentLeft(i.toDouble(), _count, w, _textDirection) +
            (w - label.size.width) / 2,
        (size.height - label.size.height) / 2,
      );
      i++;
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);
}
