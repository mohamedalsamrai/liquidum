import 'dart:math' as math;

import 'spring.dart';

/// The motion of UIKit's tab bar collapsing and expanding again, as
/// measured on iOS 26.5 from its views' presentation frames every frame:
/// minimizing (`tabBarMinimizeBehavior`), where the platter and its
/// selection collapse into a circle at the bar's leading end and the bottom
/// accessory drops into the bar's row beside it; and a search tab opening
/// into a search field, where the platter collapses the same way and the
/// search circle grows into the field.
///
/// Each value runs from 0 (expanded, closed) to 1 (collapsed, open).
class GlassTabBarMinimize {
  /// The selection's size, 54pt high to 48 and its width to 48.
  final GlassSpring size = GlassSpring(response: 0.591, dampingRatio: 0.861);

  /// The selection's center, toward the circle's: faster than its size.
  final GlassSpring center = GlassSpring(response: 0.393, dampingRatio: 0.862);

  /// The platter's own shape, faster than its selection: its width, its
  /// height and its center.
  final GlassSpring platterWidth = GlassSpring(
    response: 0.353,
    dampingRatio: 0.772,
  );
  final GlassSpring platterHeight = GlassSpring(
    response: 0.44,
    dampingRatio: 0.78,
  );
  final GlassSpring platterCenter = GlassSpring(
    response: 0.311,
    dampingRatio: 0.828,
  );

  /// The crossfade from the tabs to the circle's icon, as UIKit morphs
  /// between them: what goes out fades and blurs (radius 4pt at the end),
  /// what comes in the reverse, both squeezed into the platter's shape.
  final GlassSpring fade = GlassSpring(response: 0.255, dampingRatio: 0.86);

  /// The accessory's span, from the bar's width to the room left in its row.
  final GlassSpring accessorySpan = GlassSpring(
    response: 0.36,
    dampingRatio: 0.72,
  );

  /// The accessory's height above the row, down into it.
  final GlassSpring accessoryDrop = GlassSpring(
    response: 0.42,
    dampingRatio: 0.76,
  );

  /// The search circle growing into the search field, and the crossfade
  /// from its icon to the field's content.
  final GlassSpring searchOpen = GlassSpring(response: 0.3, dampingRatio: 0.78);
  final GlassSpring searchFade = GlassSpring(
    response: 0.255,
    dampingRatio: 0.86,
  );

  /// The field taking the keyboard: narrower, a close button beside it.
  final GlassSpring focus = GlassSpring(response: 0.3, dampingRatio: 0.8);

  /// The search circle swelling under the finger, as UIKit's glass buttons
  /// do (62pt to 79pt within 0.16s of a tap).
  final GlassSpring searchPress = GlassSpring(
    response: 0.3,
    dampingRatio: 0.8,
    value: 1,
  );

  bool _minimized = false;
  bool _searching = false;
  bool _focused = false;
  double? _now;

  // Targets taken up later than others (UIKit starts the platter's collapse
  // and the crossfade 0.09s after the selection's, and the accessory 0.1s
  // and 0.15s after; when expanding the accessory rises at once and widens
  // 67ms later), as (time, spring, target).
  final List<(double, GlassSpring, double)> _pending =
      <(double, GlassSpring, double)>[];

  bool get minimized => _minimized;

  /// Whether the search field is open.
  bool get searching => _searching;

  /// Whether the platter is collapsed into its circle: minimized, or the
  /// search field open.
  bool get collapsed => _minimized || _searching;

  List<GlassSpring> get _all => <GlassSpring>[
    size,
    center,
    platterWidth,
    platterHeight,
    platterCenter,
    fade,
    accessorySpan,
    accessoryDrop,
    searchOpen,
    searchFade,
    focus,
    searchPress,
  ];

  bool get isSettled =>
      _pending.isEmpty && _all.every((GlassSpring s) => s.isSettled);

  void _later(double at, GlassSpring spring, double to) {
    _pending.removeWhere(((double, GlassSpring, double) p) => p.$2 == spring);
    _pending.add((at, spring, to));
  }

  void _now0(GlassSpring spring, double to) {
    _pending.removeWhere(((double, GlassSpring, double) p) => p.$2 == spring);
    spring.target = to;
  }

  // Collapses or expands the platter, as the minimized state and the search
  // field call for; when minimizing, the platter follows its selection
  // after a moment.
  void _collapse(bool to, double now, {bool delayed = true}) {
    final double v = to ? 1 : 0;
    _now0(size, v);
    _now0(center, v);
    final double delay = to && delayed ? 0.09 : 0;
    for (final GlassSpring s in <GlassSpring>[
      platterWidth,
      platterHeight,
      platterCenter,
      fade,
    ]) {
      if (delay > 0) {
        _later(now + delay, s, v);
      } else {
        _now0(s, v);
      }
    }
  }

  /// Minimizes or expands from [now] (seconds, the frame clock), or at once
  /// when [animate] is false.
  void set(bool minimized, double now, {bool animate = true}) {
    if (minimized == _minimized) {
      return;
    }
    _restart(now);
    final bool wasCollapsed = collapsed;
    _minimized = minimized;
    final double to = minimized ? 1 : 0;
    if (!animate) {
      _pending.clear();
      for (final GlassSpring s in <GlassSpring>[
        size,
        center,
        platterWidth,
        platterHeight,
        platterCenter,
        fade,
      ]) {
        s.snap(collapsed ? 1 : 0);
      }
      accessorySpan.snap(to);
      accessoryDrop.snap(to);
      return;
    }
    if (collapsed != wasCollapsed) {
      _collapse(collapsed, now);
    }
    if (minimized) {
      accessorySpan.configure(0.36, 0.72);
      accessoryDrop.configure(0.42, 0.76);
      _later(now + 0.10, accessorySpan, to);
      _later(now + 0.15, accessoryDrop, to);
    } else {
      accessorySpan.configure(0.36, 0.72);
      accessoryDrop.configure(0.30, 0.72);
      _now0(accessoryDrop, to);
      _later(now + 0.067, accessorySpan, to);
    }
    _now ??= now;
  }

  /// Opens or closes the search field from [now].
  void setSearch(bool open, double now, {bool animate = true}) {
    if (open == _searching) {
      return;
    }
    _restart(now);
    final bool wasCollapsed = collapsed;
    _searching = open;
    final double to = open ? 1 : 0;
    if (!open) {
      _focused = false;
    }
    if (!animate) {
      for (final GlassSpring s in <GlassSpring>[
        size,
        center,
        platterWidth,
        platterHeight,
        platterCenter,
        fade,
      ]) {
        s.snap(collapsed ? 1 : 0);
      }
      searchOpen.snap(to);
      searchFade.snap(to);
      focus.snap(_focused ? 1 : 0);
      return;
    }
    if (collapsed != wasCollapsed) {
      // Opening the field, the platter collapses as the field grows.
      _collapse(collapsed, now, delayed: false);
    }
    _now0(searchOpen, to);
    _now0(searchFade, to);
    _now0(focus, _focused ? 1 : 0);
    _now ??= now;
  }

  /// Whether the field has the keyboard, from [now].
  void setFocus(bool focused, double now) {
    if (focused == _focused) {
      return;
    }
    _restart(now);
    _focused = focused && _searching;
    _now0(focus, _focused ? 1 : 0);
    _now ??= now;
  }

  /// The finger down on the search circle, or up.
  void pressSearch(bool down, double now) {
    _restart(now);
    searchPress.target = down ? 79 / 62 : 1;
    _now ??= now;
  }

  // A motion starting from rest starts now, not when the last one ended.
  void _restart(double now) {
    if (isSettled) {
      _now = now;
    }
  }

  /// Advances to [now]; whether anything is still moving.
  bool tick(double now) {
    final double from = _now ?? now;
    _now = now;
    // Step up to each pending start, then on from it with its new target.
    var t = from;
    _pending.sort((a, b) => a.$1.compareTo(b.$1));
    while (_pending.isNotEmpty && _pending.first.$1 <= now) {
      final (double at, GlassSpring spring, double to) = _pending.removeAt(0);
      _step(math.max(at - t, 0));
      t = math.max(t, at);
      spring.target = to;
    }
    _step(math.max(now - t, 0));
    return !isSettled;
  }

  void _step(double dt) {
    // Long gaps (the app paused) jump to the end rather than replay.
    final double step = math.min(dt, 0.1);
    for (final GlassSpring s in _all) {
      s.step(step);
    }
  }
}
