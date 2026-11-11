import 'dart:math' as math;

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/widgets.dart';

import '../lens/lens.dart';
import '../tab_bar/spring.dart';
import 'lens_seam.dart';
import 'motion.dart';

/// UIKit's switch (`UISwitch`, iOS 26): a 63 x 28pt capsule track with a
/// thumb that is the liquid lens.
///
/// ```dart
/// GlassSwitch(value: on, onChanged: (bool v) => setState(() => on = v))
/// ```
///
/// A tap toggles it: the thumb lifts into the lens for the touch and
/// travels to the other end. Pressed and dragged, the thumb follows the
/// finger between the track's ends (and stretches a little past them), and
/// the switch takes the side it is let go on. The track sweeps from its
/// off gray to [activeColor] as it toggles. With no [onChanged] the switch
/// is disabled: dimmed, and still.
class GlassSwitch extends StatefulWidget {
  const GlassSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.activeColor,
    this.thumbColor,
  });

  final bool value;

  /// Called with the new value when the switch is toggled; null disables
  /// the switch.
  final ValueChanged<bool>? onChanged;

  /// The track's color when on: the system green by default.
  final Color? activeColor;

  /// The thumb's color: white by default.
  final Color? thumbColor;

  @override
  State<GlassSwitch> createState() => _GlassSwitchState();
}

/// UIKit's numbers for the switch (iOS 26.5, measured on its layers and
/// frame by frame; see doc/comparison/glass-widgets/stage4).
abstract final class _SwitchMetrics {
  /// The track: a 63 x 28 capsule.
  static const Size size = Size(63, 28);

  /// The thumb's inset from the track's edge, and its size at rest: 37 x 24
  /// at x 2 (off) to 24 (on).
  static const double inset = 2;
  static const Size thumb = Size(37, 24);

  /// The lens while lifted: the thumb grown about its center.
  static const Size thumbLifted = Size(58, 38.33);

  /// How far the lifted lens follows the finger past the track's end.
  static const double rubberBand = 0.31;

  // Colors: the off track (60, 60, 67 at 0.30 light; 235, 235, 245 at 0.30
  // dark), the system green on, the thumb white in both appearances.
  static const Color onLight = Color(0xFF34C759);
  static const Color onDark = Color(0xFF30D158);
  static const Color offLight = Color(0x4D3C3C43);
  static const Color offDark = Color(0x4DEBEBF5);
  static const Color thumbColor = Color(0xFFFFFFFF);

  /// Disabled: everything at half its alpha.
  static const double disabledOpacity = 0.5;

  /// The thumb's travel (stiffness, damping): critically damped, 0.3s.
  static const (double, double) travel = (452, 44.8);

  /// The track's color sweep (stiffness, damping): critically damped, about
  /// a second.
  static const (double, double) sweep = (49, 14);

  /// The thumb's lens: UIKit's small liquid lens, lifting on a spring of
  /// its own (13% over at 0.12s), falling the moment the finger leaves,
  /// and lifted for at least 0.15s by a tap.
  static const (double, double) liftSpring = (800, 31);
  static const (double, double) unliftSpring = (209, 19.5);
  static const double tapLift = 0.15;
  static const LensOptics optics = LensOptics.small(38.33);
}

class _GlassSwitchState extends State<GlassSwitch>
    with SingleTickerProviderStateMixin {
  final GlassSpring _position = GlassSpring(
    response: physicalSpring(
      _SwitchMetrics.travel.$1,
      _SwitchMetrics.travel.$2,
    ).$1,
    dampingRatio: physicalSpring(
      _SwitchMetrics.travel.$1,
      _SwitchMetrics.travel.$2,
    ).$2,
    tolerance: 1e-3,
  );
  final GlassSpring _sweep = GlassSpring(
    response: physicalSpring(
      _SwitchMetrics.sweep.$1,
      _SwitchMetrics.sweep.$2,
    ).$1,
    dampingRatio: physicalSpring(
      _SwitchMetrics.sweep.$1,
      _SwitchMetrics.sweep.$2,
    ).$2,
    tolerance: 1e-3,
  );
  final LensLift _lift = LensLift(
    liftSpring: _SwitchMetrics.liftSpring,
    unliftSpring: _SwitchMetrics.unliftSpring,
    hangTime: 0,
    minimumLift: _SwitchMetrics.tapLift,
  );
  final LensFlex _flex = LensFlex.forWidth(_SwitchMetrics.thumb.width);
  late final ControlMotion _motion = ControlMotion(
    this,
    <GlassSpring>[_position, _sweep],
    lift: _lift,
    flex: _flex,
    position: () => _thumbX,
  );

  bool _dragging = false;
  double _dragFrom = 0;
  double _dragX = 0;
  double _rubber = 0;
  bool _rtl = false;

  bool get _enabled => widget.onChanged != null;

  /// The thumb's travel along the track (points): 22.
  static final double _travel =
      _SwitchMetrics.size.width -
      2 * _SwitchMetrics.inset -
      _SwitchMetrics.thumb.width;

  @override
  void initState() {
    super.initState();
    _position.snap(widget.value ? 1 : 0);
    _sweep.snap(widget.value ? 1 : 0);
  }

  @override
  void didUpdateWidget(GlassSwitch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value && !_dragging) {
      _position.target = widget.value ? 1 : 0;
      _sweep.target = widget.value ? 1 : 0;
      _motion.wake();
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    _lift.dispose();
    super.dispose();
  }

  // The thumb's center along the track, as drawn (points, left to right).
  double get _thumbX {
    final double p = _position.value.clamp(0.0, 1.0);
    final double x =
        _SwitchMetrics.inset + _SwitchMetrics.thumb.width / 2 + p * _travel;
    return (_rtl ? _SwitchMetrics.size.width - x : x) + _rubber + _flex.drift;
  }

  void _down(DragDownDetails details) {
    _lift.down();
    _motion.wake();
  }

  void _start(DragStartDetails details) {
    _dragging = true;
    _dragFrom = _position.value;
    _dragX = details.localPosition.dx;
  }

  void _update(DragUpdateDetails details) {
    if (!_dragging) {
      return;
    }
    final double dx = (details.localPosition.dx - _dragX) * (_rtl ? -1 : 1);
    final double raw = _dragFrom + dx / _travel;
    final double p = raw.clamp(0.0, 1.0);
    _position.snap(p);
    // Past the end, the lifted lens follows the finger by a fraction.
    _rubber = _SwitchMetrics.rubberBand * (raw - p) * _travel * (_rtl ? -1 : 1);
    // The track sweeps once the thumb crosses the middle.
    _sweep.target = p > 0.5 ? 1 : 0;
    _motion.wake();
  }

  void _end(DragEndDetails details) {
    if (!_dragging) {
      return;
    }
    _dragging = false;
    _rubber = 0;
    _commit(_position.value > 0.5);
    _release();
  }

  void _cancel() {
    _dragging = false;
    _rubber = 0;
    _aim(widget.value);
    _release();
  }

  void _tapUp(TapUpDetails details) => _commit(!widget.value);

  // Tells the owner and heads for [on]; if the owner keeps the old value,
  // the thumb comes back once the frame has shown it.
  void _commit(bool on) {
    if (on != widget.value) {
      widget.onChanged?.call(on);
    }
    _aim(on);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_dragging) {
        _aim(widget.value);
      }
    });
  }

  void _aim(bool on) {
    _position.target = on ? 1 : 0;
    _sweep.target = on ? 1 : 0;
    _motion.wake();
  }

  // The finger left: the lens falls back.
  void _release() {
    _lift.up();
    _motion.wake();
  }

  @override
  Widget build(BuildContext context) {
    final bool dark =
        MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    final bool still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _lift.reduceMotion = still;
    _motion.reduceMotion = still;
    _rtl = Directionality.maybeOf(context) == TextDirection.rtl;
    final double opacity = _enabled ? 1 : _SwitchMetrics.disabledOpacity;
    final Color on =
        widget.activeColor ??
        (dark ? _SwitchMetrics.onDark : _SwitchMetrics.onLight);
    final Color off = dark ? _SwitchMetrics.offDark : _SwitchMetrics.offLight;
    const Size size = _SwitchMetrics.size;
    return Semantics(
      toggled: widget.value,
      enabled: _enabled,
      onTap: _enabled ? () => widget.onChanged!(!widget.value) : null,
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
        child: SizedBox.fromSize(
          size: size,
          child: ListenableBuilder(
            listenable: _motion,
            builder: (BuildContext context, _) {
              // The thumb grows toward its lifted size with the lens's
              // bounds (overshooting as they do), about its center.
              final double g = math.max(_lift.growth, -0.25);
              final Size thumb = Size.lerp(
                _SwitchMetrics.thumb,
                _SwitchMetrics.thumbLifted,
                g,
              )!;
              final double p = _position.value.clamp(0.0, 1.0);
              double cx =
                  _SwitchMetrics.inset +
                  _SwitchMetrics.thumb.width / 2 +
                  p * _travel;
              if (_rtl) {
                cx = size.width - cx;
              }
              // The lens over the track: the track is what it refracts.
              return ControlLens(
                rect: Rect.fromCenter(
                  center: Offset(cx, size.height / 2),
                  width: thumb.width,
                  height: thumb.height,
                ),
                lift: _lift.lift,
                optics: _SwitchMetrics.optics,
                flexScale: _flex.scale,
                drift: Offset(_rubber + _flex.drift, 0),
                opacity: opacity,
                color: widget.thumbColor ?? _SwitchMetrics.thumbColor,
                child: DecoratedBox(
                  decoration: ShapeDecoration(
                    shape: const StadiumBorder(),
                    color: dimmed(
                      Color.lerp(off, on, _sweep.value.clamp(0.0, 1.0))!,
                      opacity,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
