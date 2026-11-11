import 'dart:math' as math;

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/widgets.dart';

import '../lens/lens.dart';
import '../tab_bar/spring.dart';
import '../tab_bar/style.dart';
import 'lens_seam.dart';
import 'motion.dart';

/// UIKit's slider (`UISlider`, iOS 26): a thin track, tinted up to the
/// value, with a thumb that is the liquid lens.
///
/// ```dart
/// GlassSlider(value: volume, onChanged: (double v) => setState(() => volume = v))
/// ```
///
/// Dragged by its thumb, the thumb lifts into the lens and follows the
/// finger along the track; as UIKit's, a touch on the track away from the
/// thumb does nothing. [divisions] snaps the value to that many steps.
/// With no [onChanged] the slider is disabled: dimmed, and still. It fills
/// the width it is given, 34pt tall.
class GlassSlider extends StatefulWidget {
  const GlassSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 1,
    this.divisions,
    this.activeColor,
    this.thumbColor,
    this.onChangeStart,
    this.onChangeEnd,
  }) : assert(min <= max),
       assert(divisions == null || divisions > 0);

  final double value;

  /// Called with the new value as the thumb is dragged; null disables the
  /// slider.
  final ValueChanged<double>? onChanged;
  final double min;
  final double max;

  /// Steps the value snaps to, if any.
  final int? divisions;

  /// The track's color up to the value: the system blue by default.
  final Color? activeColor;

  /// The thumb's color: white by default.
  final Color? thumbColor;

  /// Called with the value when a drag starts and when it ends.
  final ValueChanged<double>? onChangeStart;
  final ValueChanged<double>? onChangeEnd;

  @override
  State<GlassSlider> createState() => _GlassSliderState();
}

/// UIKit's numbers for the slider (iOS 26.5, measured on its layers and
/// frame by frame; see doc/comparison/glass-widgets/stage4).
abstract final class _SliderMetrics {
  static const double height = 34;

  /// The track: 6pt tall at y 14, its full width, rounded.
  static const double trackHeight = 6;
  static const double trackTop = 14;

  /// The thumb at rest: 37 x 24 at y 5, its center at value x (width -
  /// 37) from the left.
  static const Size thumb = Size(37, 24);

  /// The lens while lifted: the thumb grown about its center.
  static const Size thumbLifted = Size(57.33, 37);

  /// How far past the thumb a touch still takes it (points). UIKit iOS
  /// 26.5, to confirm: a touch 100pt away does nothing; the slop is
  /// unmeasured.
  static const double thumbReach = 8;

  // Colors: the track past the value (black at 0.10 light, white at 0.10
  // dark), the thumb white in both appearances, with its shadow (0.14,
  // radius 5, 1pt down).
  static const Color maxTrackLight = Color(0x1A000000);
  static const Color maxTrackDark = Color(0x1AFFFFFF);
  static const Color thumbColor = Color(0xFFFFFFFF);
  static const List<BoxShadow> thumbShadow = <BoxShadow>[
    BoxShadow(color: Color(0x24000000), blurRadius: 8, offset: Offset(0, 1)),
  ];

  /// Disabled: everything at half its alpha.
  static const double disabledOpacity = 0.5;

  /// The thumb's lens: UIKit's small liquid lens, lifting on touch-down on
  /// the thumb (13% over at 0.12s) and falling the moment the finger
  /// leaves, on UIKit's small unlift spring.
  static const (double, double) liftSpring = (800, 31);
  static const LensOptics optics = LensOptics.small(37);
}

class _GlassSliderState extends State<GlassSlider>
    with SingleTickerProviderStateMixin {
  final LensLift _lift = LensLift(
    liftSpring: _SliderMetrics.liftSpring,
    hangTime: 0,
  );
  final LensFlex _flex = LensFlex.forWidth(_SliderMetrics.thumb.width);
  late final ControlMotion _motion = ControlMotion(
    this,
    const <GlassSpring>[],
    lift: _lift,
    flex: _flex,
    position: () => _centerX(_fraction) + _flex.drift,
  );

  // The slider's width, from its last layout.
  double _width = 0;
  bool _rtl = false;
  bool _armed = false;
  bool _dragging = false;
  double _dragFrom = 0;
  double _dragX = 0;
  double? _sent;

  bool get _enabled => widget.onChanged != null;

  @override
  void dispose() {
    _motion.dispose();
    _lift.dispose();
    super.dispose();
  }

  double get _range => widget.max - widget.min;

  /// The value as a fraction of the track, 0 to 1.
  double get _fraction =>
      _range <= 0 ? 0 : ((widget.value - widget.min) / _range).clamp(0.0, 1.0);

  // The track's length the thumb's center travels (points).
  double get _trackLength => _width - _SliderMetrics.thumb.width;

  // The thumb's center along the track, left to right, for a fraction.
  double _centerX(double fraction) {
    final double f = _rtl ? 1 - fraction : fraction;
    return _SliderMetrics.thumb.width / 2 + f * _trackLength;
  }

  double _snap(double fraction) {
    final int? n = widget.divisions;
    final double f = fraction.clamp(0.0, 1.0);
    return n == null ? f : (f * n).round() / n;
  }

  void _down(DragDownDetails details) {
    final double cx = _centerX(_fraction);
    final double reach =
        _SliderMetrics.thumb.width / 2 + _SliderMetrics.thumbReach;
    _armed = (details.localPosition.dx - cx).abs() <= reach;
    if (_armed) {
      _lift.down();
      _motion.wake();
    }
  }

  void _start(DragStartDetails details) {
    if (!_armed) {
      return;
    }
    _dragging = true;
    _dragFrom = _fraction;
    _dragX = details.localPosition.dx;
    _sent = null;
    widget.onChangeStart?.call(widget.value);
  }

  void _update(DragUpdateDetails details) {
    if (!_dragging || _trackLength <= 0) {
      return;
    }
    final double dx = (details.localPosition.dx - _dragX) * (_rtl ? -1 : 1);
    final double value =
        widget.min + _snap(_dragFrom + dx / _trackLength) * _range;
    if (value != (_sent ?? widget.value)) {
      _sent = value;
      widget.onChanged?.call(value);
      _motion.wake();
    }
  }

  void _end(DragEndDetails details) {
    if (_dragging) {
      _dragging = false;
      widget.onChangeEnd?.call(_sent ?? widget.value);
    }
    _release();
  }

  void _cancel() {
    if (_dragging) {
      _dragging = false;
      widget.onChangeEnd?.call(_sent ?? widget.value);
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

  void _adjust(double by) {
    final double value =
        widget.min + _snap(_fraction + by).clamp(0.0, 1.0) * _range;
    if (value != widget.value) {
      widget.onChanged?.call(value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool dark =
        MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    final bool still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _lift.reduceMotion = still;
    _motion.reduceMotion = still;
    _rtl = Directionality.maybeOf(context) == TextDirection.rtl;
    final double opacity = _enabled ? 1 : _SliderMetrics.disabledOpacity;
    final Color active = dimmed(
      widget.activeColor ??
          GlassTabBarStyle.resolve(GlassTabBarStyle.systemBlue, dark: dark),
      opacity,
    );
    final Color rest = dimmed(
      dark ? _SliderMetrics.maxTrackDark : _SliderMetrics.maxTrackLight,
      opacity,
    );
    final double step = widget.divisions == null ? 0.1 : 1 / widget.divisions!;
    final String percent = '${(_fraction * 100).round()}%';
    return Semantics(
      slider: true,
      enabled: _enabled,
      value: percent,
      increasedValue:
          '${(_snap(_fraction + step).clamp(0.0, 1.0) * 100).round()}%',
      decreasedValue:
          '${(_snap(_fraction - step).clamp(0.0, 1.0) * 100).round()}%',
      onIncrease: _enabled ? () => _adjust(step) : null,
      onDecrease: _enabled ? () => _adjust(-step) : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Drags count from the touch, not from where they were told
        // apart from a tap.
        dragStartBehavior: DragStartBehavior.down,
        onHorizontalDragDown: _enabled ? _down : null,
        onHorizontalDragStart: _enabled ? _start : null,
        onHorizontalDragUpdate: _enabled ? _update : null,
        onHorizontalDragEnd: _enabled ? _end : null,
        onHorizontalDragCancel: _enabled ? _cancel : null,
        child: SizedBox(
          height: _SliderMetrics.height,
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              _width = constraints.maxWidth.isFinite
                  ? constraints.maxWidth
                  : 2 * _SliderMetrics.thumb.width;
              return ListenableBuilder(
                listenable: _motion,
                builder: (BuildContext context, _) {
                  // The thumb grows toward its lifted size with the lens's
                  // bounds (overshooting as they do), about its center.
                  final double g = math.max(_lift.growth, -0.25);
                  final Size thumb = Size.lerp(
                    _SliderMetrics.thumb,
                    _SliderMetrics.thumbLifted,
                    g,
                  )!;
                  final double cx = _centerX(_fraction);
                  final double split = _rtl ? _width - cx : cx;
                  // The lens over the track: the track is what it
                  // refracts.
                  return ControlLens(
                    rect: Rect.fromCenter(
                      center: Offset(cx, _SliderMetrics.height / 2),
                      width: thumb.width,
                      height: thumb.height,
                    ),
                    lift: _lift.lift,
                    optics: _SliderMetrics.optics,
                    flexScale: _flex.scale,
                    drift: Offset(_flex.drift, 0),
                    opacity: opacity,
                    color: widget.thumbColor ?? _SliderMetrics.thumbColor,
                    shadows: _SliderMetrics.thumbShadow,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: <Widget>[
                        // The track: gray over its full width, and the
                        // active color from the start to the thumb.
                        Positioned(
                          left: 0,
                          right: 0,
                          top: _SliderMetrics.trackTop,
                          height: _SliderMetrics.trackHeight,
                          child: DecoratedBox(
                            decoration: ShapeDecoration(
                              shape: const StadiumBorder(),
                              color: rest,
                            ),
                          ),
                        ),
                        Positioned.directional(
                          textDirection: _rtl
                              ? TextDirection.rtl
                              : TextDirection.ltr,
                          start: 0,
                          width: split.clamp(0.0, double.infinity),
                          top: _SliderMetrics.trackTop,
                          height: _SliderMetrics.trackHeight,
                          child: DecoratedBox(
                            decoration: ShapeDecoration(
                              shape: const StadiumBorder(),
                              color: active,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}
