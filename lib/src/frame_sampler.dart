import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Reads the backdrop as frames are drawn: [sample] runs after a drawn frame,
/// at most once per [interval], and once more after the last frame of a
/// burst, so that what was drawn last is always measured.
///
/// It waits on the frames themselves, through one post-frame callback at a
/// time: while no frames are drawn, nothing runs (no timer, no snapshot, no
/// readback). The only timer is the throttle's, a one-shot started with each
/// sample. While the app is not resumed, frames are ignored; on resume it
/// samples once more, after the next frame.
class FrameSampler with WidgetsBindingObserver {
  FrameSampler({required this.interval, required this.sample}) {
    final WidgetsBinding binding = WidgetsBinding.instance;
    final AppLifecycleState? state = binding.lifecycleState;
    _paused = state != null && state != AppLifecycleState.resumed;
    binding
      ..addObserver(this)
      ..addPostFrameCallback(_frame);
  }

  /// The shortest time between two samples.
  final Duration interval;

  /// Reads the backdrop. The next sample waits until it completes.
  final Future<void> Function() sample;

  /// Called as each sample starts, for tests.
  @visibleForTesting
  static void Function(FrameSampler sampler)? debugOnSample;

  bool _paused = false;
  bool _disposed = false;

  // Whether a frame was drawn since the last sample started.
  bool _due = false;
  bool _running = false;

  // Running from each sample's start for [interval]: a frame drawn meanwhile
  // is sampled when it ends.
  Timer? _throttle;

  void _frame(Duration _) {
    if (_disposed) {
      return;
    }
    SchedulerBinding.instance.addPostFrameCallback(_frame);
    if (_paused) {
      return;
    }
    _due = true;
    _run();
  }

  void _run() {
    if (!_due || _running || _throttle != null || _paused || _disposed) {
      return;
    }
    _due = false;
    _running = true;
    _throttle = Timer(interval, () {
      _throttle = null;
      _run();
    });
    debugOnSample?.call(this);
    sample().whenComplete(() {
      _running = false;
      _run();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final bool paused = state != AppLifecycleState.resumed;
    if (paused == _paused) {
      return;
    }
    _paused = paused;
    if (paused) {
      _throttle?.cancel();
      _throttle = null;
      _due = false;
    } else {
      // A fresh sample after the next frame.
      SchedulerBinding.instance.ensureVisualUpdate();
    }
  }

  void dispose() {
    _disposed = true;
    _throttle?.cancel();
    _throttle = null;
    WidgetsBinding.instance.removeObserver(this);
  }
}
