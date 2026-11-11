import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../lens/lens.dart';
import '../tab_bar/spring.dart';

/// Steps a control's springs, its thumb's [lift] into the lens and the
/// thumb's [flex] (its soft body, kicked by how the thumb moves on screen,
/// read from [position] each frame), every frame while any of them moves,
/// and notifies after every step. Stops on its own once all is still.
class ControlMotion extends ChangeNotifier {
  ControlMotion(
    TickerProvider vsync,
    this.springs, {
    this.lift,
    this.flex,
    this.position,
  }) {
    _ticker = vsync.createTicker(_tick);
  }

  final List<GlassSpring> springs;

  /// The thumb's lift, ticked on the same clock as the springs.
  final LensLift? lift;

  /// The thumb's flex, kicked by the change in its velocity: where the
  /// thumb is along its motion (points), read each frame.
  final LensFlex? flex;
  final double Function()? position;

  /// Reduce Motion: the thumb does not flex.
  bool reduceMotion = false;

  late final Ticker _ticker;
  Duration? _last;
  double? _lastPosition;
  double _velocity = 0;

  // Seconds run so far: the clock the lift keeps.
  double _time = 0;

  bool get isActive =>
      (lift?.isActive ?? false) ||
      !(flex?.isSettled ?? true) ||
      springs.any((GlassSpring s) => !s.isSettled);

  /// Starts stepping, if not already.
  void wake() {
    if (!_ticker.isActive) {
      _last = null;
      _lastPosition = null;
      _velocity = 0;
      _ticker.start();
    }
  }

  void _tick(Duration elapsed) {
    final double dt = _last == null
        ? 0
        : ((elapsed - _last!).inMicroseconds / 1e6).clamp(0.0, 0.1);
    _last = elapsed;
    _time += dt;
    // The thumb's velocity over the last frame, from where it was drawn.
    final double? x = position?.call();
    if (x != null) {
      if (_lastPosition != null && dt > 0) {
        _velocity = (x - _lastPosition!) / dt;
      }
      _lastPosition = x;
    }
    final LensFlex? flex = this.flex;
    flex?.aim();
    // Slices of at most 4ms, so the springs' exact steps stay smooth
    // however late a frame comes.
    final int slices = math.max(1, (dt / 0.004).ceil());
    final double h = dt / slices;
    for (var i = 0; i < slices; i++) {
      for (final GlassSpring s in springs) {
        s.step(h);
      }
      if (flex != null) {
        for (final GlassSpring s in flex.springs) {
          s.step(h);
        }
        flex.kick(_velocity, h, reduceMotion: reduceMotion);
      }
    }
    lift?.tick(_time);
    notifyListeners();
    if (!isActive) {
      _ticker.stop();
      _last = null;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }
}

/// A spring given as UIKit gives it (mass 1; stiffness, damping), as a
/// [GlassSpring]'s (response, damping ratio).
(double, double) physicalSpring(double stiffness, double damping) =>
    (2 * math.pi / math.sqrt(stiffness), damping / (2 * math.sqrt(stiffness)));
