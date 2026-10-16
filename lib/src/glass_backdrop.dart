import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'frame_sampler.dart';

/// Marks the content that glass floats over, so glass can tell how bright it
/// is (see [GlassBrightness]).
///
/// Wrap only the content, not the glass itself: glass finds the backdrop that
/// lies under it, typically a sibling painted before it in a [Stack].
class GlassBackdrop extends StatefulWidget {
  const GlassBackdrop({super.key, required this.child});

  final Widget child;

  static final Set<GlassBackdropState> _mounted = <GlassBackdropState>{};

  @override
  State<GlassBackdrop> createState() => GlassBackdropState();
}

/// The most recently mounted backdrop that lies under [rect], in global
/// logical coordinates.
GlassBackdropState? glassBackdropUnder(Rect rect) {
  GlassBackdropState? found;
  for (final GlassBackdropState backdrop in GlassBackdrop._mounted) {
    final Rect? bounds = backdrop._bounds;
    if (bounds != null && bounds.overlaps(rect)) {
      found = backdrop;
    }
  }
  return found;
}

class GlassBackdropState extends State<GlassBackdrop> {
  final GlobalKey _boundary = GlobalKey();

  @override
  void initState() {
    super.initState();
    GlassBackdrop._mounted.add(this);
  }

  @override
  void dispose() {
    GlassBackdrop._mounted.remove(this);
    super.dispose();
  }

  Rect? get _bounds {
    final RenderObject? object = _boundary.currentContext?.findRenderObject();
    if (object is! RenderBox || !object.attached || !object.hasSize) {
      return null;
    }
    return MatrixUtils.transformRect(
      object.getTransformTo(null),
      Offset.zero & object.size,
    );
  }

  /// Resolution of the snapshot the luminance is read from, relative to
  /// logical pixels. Coarse is enough for an average.
  static const double _ratio = 0.125;

  /// Average luminance, 0 to 1, of the backdrop within [rect] (in global
  /// logical coordinates), or null if it cannot be read right now.
  Future<double?> luminance(Rect rect) async {
    // Snapshot only a painted tree; with no frame pending it already is.
    if (SchedulerBinding.instance.hasScheduledFrame) {
      await SchedulerBinding.instance.endOfFrame;
    }
    final RenderObject? object = _boundary.currentContext?.findRenderObject();
    if (object is! _RenderBackdropBoundary || !object.attached) {
      return null;
    }
    final ui.Image image = await object.snapshot(
      Offset.zero & object.size,
      _ratio,
    );
    try {
      final ByteData? data = await image.toByteData();
      if (data == null) {
        return null;
      }
      final Rect local = rect.shift(-object.localToGlobal(Offset.zero));
      final int x0 = (local.left * _ratio).floor().clamp(0, image.width);
      final int x1 = (local.right * _ratio).ceil().clamp(0, image.width);
      final int y0 = (local.top * _ratio).floor().clamp(0, image.height);
      final int y1 = (local.bottom * _ratio).ceil().clamp(0, image.height);
      var sum = 0.0;
      var count = 0;
      for (var y = y0; y < y1; y++) {
        for (var x = x0; x < x1; x++) {
          final int i = (y * image.width + x) * 4;
          sum +=
              0.2126 * data.getUint8(i) +
              0.7152 * data.getUint8(i + 1) +
              0.0722 * data.getUint8(i + 2);
          count++;
        }
      }
      return count == 0 ? null : sum / count / 255;
    } finally {
      image.dispose();
    }
  }

  /// The backdrop's mean luma (Rec. 709 on its colors, 0 to 1) over
  /// [area], in global logical coordinates, read from a coarse snapshot of
  /// just that area; null if it cannot be read right now.
  Future<double?> meanLuma(Rect area, {double ratio = 0.25}) async {
    final RenderObject? object = _boundary.currentContext?.findRenderObject();
    if (object is! _RenderBackdropBoundary || !object.attached) {
      return null;
    }
    final Rect local = area
        .shift(-object.localToGlobal(Offset.zero))
        .intersect(Offset.zero & object.size);
    if (local.isEmpty) {
      return null;
    }
    final ui.Image image = await object.snapshot(local, ratio);
    try {
      final ByteData? data = await image.toByteData();
      if (data == null) {
        return null;
      }
      var sum = 0.0;
      final int n = image.width * image.height;
      for (var i = 0; i < n * 4; i += 4) {
        sum +=
            0.2126 * data.getUint8(i) +
            0.7152 * data.getUint8(i + 1) +
            0.0722 * data.getUint8(i + 2);
      }
      return n == 0 ? null : sum / n / 255;
    } finally {
      image.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return _BackdropBoundary(key: _boundary, child: widget.child);
  }
}

/// A repaint boundary whose layer can be snapshot in part.
class _BackdropBoundary extends SingleChildRenderObjectWidget {
  const _BackdropBoundary({super.key, super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderBackdropBoundary();
}

class _RenderBackdropBoundary extends RenderProxyBox {
  @override
  bool get isRepaintBoundary => true;

  /// [rect] (local) of what was last painted, at [ratio] pixels per point.
  Future<ui.Image> snapshot(Rect rect, double ratio) =>
      (layer! as OffsetLayer).toImage(rect, pixelRatio: ratio);
}

/// Picks light or dark glass for what is behind it, the way iOS bars do: it
/// follows the system appearance, except that over very dark content light
/// glass turns dark, and over very light content dark glass turns light.
///
/// [builder] gets 0 for light glass and 1 for dark, animating in between.
/// Without a [GlassBackdrop] under it, it follows the system appearance.
class GlassBrightness extends StatefulWidget {
  const GlassBrightness({super.key, required this.builder, this.child});

  final ValueWidgetBuilder<double> builder;
  final Widget? child;

  @override
  State<GlassBrightness> createState() => _GlassBrightnessState();
}

class _GlassBrightnessState extends State<GlassBrightness>
    with SingleTickerProviderStateMixin {
  static const _interval = Duration(milliseconds: 250);

  // Thresholds on average backdrop luminance, as UIKit's iOS 26.5 tab bar
  // switches (see GlassAppearance): with the system light, dark below 0.210
  // and light again above 0.492; with it dark, light above 0.867 and dark
  // again below 0.584.
  static const double _enterDark = 0.210, _leaveDark = 0.492;
  static const double _enterLight = 0.867, _leaveLight = 0.584;

  late final AnimationController _dark = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  );
  // Reads the backdrop every 250ms while frames are being drawn.
  late final FrameSampler _sampler;
  bool _shown = false;
  bool _sampling = false;
  Brightness _system = Brightness.light;
  Brightness? _override;

  Brightness get _target => _override ?? _system;

  @override
  void initState() {
    super.initState();
    _sampler = FrameSampler(interval: _interval, sample: _sample);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _system = MediaQuery.platformBrightnessOf(context);
    _override = null;
    _show(animate: _shown);
    _shown = true;
  }

  void _show({bool animate = true}) {
    final double to = _target == Brightness.dark ? 1 : 0;
    if (animate) {
      _dark.animateTo(to, curve: Curves.easeInOut);
    } else {
      _dark.value = to;
    }
  }

  Future<void> _sample() async {
    final RenderObject? box = context.findRenderObject();
    if (_sampling || box is! RenderBox || !box.attached || !box.hasSize) {
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
      final double? luminance = await backdrop.luminance(rect);
      if (!mounted || luminance == null) {
        return;
      }
      final Brightness? previous = _override;
      if (_system == Brightness.light) {
        if (luminance < _enterDark) {
          _override = Brightness.dark;
        } else if (luminance > _leaveDark) {
          _override = null;
        }
      } else {
        if (luminance > _enterLight) {
          _override = Brightness.light;
        } else if (luminance < _leaveLight) {
          _override = null;
        }
      }
      if (_override != previous) {
        _show();
      }
    } finally {
      _sampling = false;
    }
  }

  @override
  void dispose() {
    _sampler.dispose();
    _dark.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _dark,
      builder: (BuildContext context, Widget? child) =>
          widget.builder(context, _dark.value, child),
      child: widget.child,
    );
  }
}
