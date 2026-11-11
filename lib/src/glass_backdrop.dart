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
/// lies under it, typically a sibling painted before it in a [Stack]. All
/// the glass over a backdrop then reads the screen once for its frost,
/// instead of once each, which keeps a page with many glass smooth.
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

/// How the glass over a backdrop shares its reads of the screen: the frost
/// of every such glass is drawn into [frosts], which the backdrop draws
/// right after its content (in [host]'s coordinates), from one read
/// ([frostKey]); then each glass is drawn where it is, from one read of the
/// backdrop and all the frost ([glassKey]). Two reads in all, instead of two
/// for each glass. For Liquidum's glass; not exported.
class GlassShare {
  GlassShare._(this._backdrop);

  final GlassBackdropState _backdrop;

  /// The frost's read, and the glass's.
  final BackdropKey frostKey = BackdropKey();
  final BackdropKey glassKey = BackdropKey();

  /// Where the frost of the glass goes.
  final ContainerLayer frosts = ContainerLayer();

  /// The render object [frosts] is drawn by (its coordinates).
  RenderObject? get host => _backdrop._host.currentContext?.findRenderObject();

  // The glass that shares this frame, where they are (global).
  int _frame = -1;
  final List<Rect> _claimed = <Rect>[];
}

/// The reads [glass] (at [rect], in global logical coordinates) can share
/// with the other glass over the same backdrop; null when it reads the
/// screen for itself.
///
/// Glass shares when it is drawn over a [GlassBackdrop] from beside it (a
/// sibling of the backdrop, or within one, as in a [Stack]): it sees the
/// backdrop and the frost of all such glass, but not other glass (glass
/// does not see glass, as in UIKit). Glass inside the backdrop, or
/// elsewhere (where content may be drawn between the backdrop and it), and
/// glass over glass drawn before it, reads its own.
GlassShare? glassShareFor(RenderObject glass, Rect rect) {
  final GlassBackdropState? backdrop = glassBackdropUnder(rect);
  if (backdrop == null || backdrop._holds(glass)) {
    return null;
  }
  final GlassShare share = backdrop._share;
  final RenderObject? host = share.host;
  final RenderObject? beside = host?.parent;
  if (host == null || beside == null) {
    return null;
  }
  var within = false;
  for (RenderObject? o = glass.parent; o != null; o = o.parent) {
    if (identical(o, beside)) {
      within = true;
      break;
    }
  }
  // Its frost is drawn in the backdrop's coordinates: only moved, not
  // turned or scaled from them.
  if (!within ||
      MatrixUtils.getAsTranslation(glass.getTransformTo(host)) == null) {
    return null;
  }
  final int frame = GlassBackdropState._frames;
  if (share._frame != frame) {
    share
      .._frame = frame
      .._claimed.clear();
  }
  for (final Rect other in share._claimed) {
    if (other.overlaps(rect)) {
      return null;
    }
  }
  share._claimed.add(rect);
  return share;
}

class GlassBackdropState extends State<GlassBackdrop> {
  final GlobalKey _boundary = GlobalKey();
  final GlobalKey _host = GlobalKey();
  late final GlassShare _share = GlassShare._(this);

  // Whether [object] is part of the backdrop.
  bool _holds(RenderObject object) {
    final RenderObject? boundary = _boundary.currentContext?.findRenderObject();
    for (RenderObject? o = object; o != null; o = o.parent) {
      if (identical(o, boundary)) {
        return true;
      }
    }
    return false;
  }

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

  /// Resolution of the snapshot the backdrop is read from, relative to
  /// logical pixels. Coarse is enough for an average.
  static const double _ratio = 0.25;

  // Frames drawn so far, by any view: a snapshot shows the backdrop as of
  // the frame it was taken after.
  static int _frames = 0;
  static bool _counting = false;

  static void _countFrames() {
    if (!_counting) {
      _counting = true;
      SchedulerBinding.instance.addPersistentFrameCallback((_) => _frames++);
    }
  }

  // The last snapshot, and the one being taken. Every reader shares them:
  // the backdrop is snapshot at most once per drawn frame, and one at a
  // time, however many glasses read it (each snapshot paints the whole
  // backdrop again).
  _Snapshot? _last;
  Future<_Snapshot?>? _taking;

  /// The backdrop as of the latest drawn frame.
  Future<_Snapshot?> _snapshot() async {
    _countFrames();
    // Snapshot only a painted tree; with no frame pending it already is.
    if (SchedulerBinding.instance.hasScheduledFrame) {
      await SchedulerBinding.instance.endOfFrame;
    }
    while (true) {
      final _Snapshot? last = _last;
      if (last != null && last.frame == _frames) {
        return last;
      }
      final Future<_Snapshot?>? taking = _taking;
      if (taking == null) {
        break;
      }
      final _Snapshot? shot = await taking;
      if (shot == null || shot.frame == _frames) {
        return shot;
      }
    }
    final Future<_Snapshot?> taking = _take();
    _taking = taking;
    try {
      final _Snapshot? shot = await taking;
      if (shot != null) {
        _last = shot;
      }
      return shot;
    } finally {
      _taking = null;
    }
  }

  Future<_Snapshot?> _take() async {
    final RenderObject? object = _boundary.currentContext?.findRenderObject();
    if (object is! _RenderBackdropBoundary || !object.attached) {
      return null;
    }
    final int frame = _frames;
    // Where the backdrop is, read now: it may be gone once the snapshot is.
    final Offset origin = object.localToGlobal(Offset.zero);
    final ui.Image image = await object.snapshot(
      Offset.zero & object.size,
      _ratio,
    );
    try {
      final ByteData? data = await image.toByteData();
      if (data == null) {
        return null;
      }
      return _Snapshot(frame, origin, image.width, image.height, data);
    } finally {
      image.dispose();
    }
  }

  /// Average luminance, 0 to 1, of the backdrop within [rect] (in global
  /// logical coordinates), or null if it cannot be read right now.
  Future<double?> luminance(Rect rect) => meanLuma(rect);

  /// The backdrop's mean luma (Rec. 709 on its colors, 0 to 1) over
  /// [area], in global logical coordinates, read from a coarse snapshot of
  /// the backdrop; null if it cannot be read right now.
  Future<double?> meanLuma(Rect area) async {
    final _Snapshot? shot = await _snapshot();
    return shot?.meanLuma(area);
  }

  @override
  Widget build(BuildContext context) {
    _countFrames();
    return _BackdropHost(
      key: _host,
      frosts: _share.frosts,
      child: _BackdropBoundary(key: _boundary, child: widget.child),
    );
  }
}

/// Draws the frost of the glass over the backdrop, after the backdrop.
class _BackdropHost extends SingleChildRenderObjectWidget {
  const _BackdropHost({super.key, required this.frosts, super.child});

  final ContainerLayer frosts;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderBackdropHost(frosts);
}

class _RenderBackdropHost extends RenderProxyBox {
  _RenderBackdropHost(this._frosts);

  final ContainerLayer _frosts;
  final LayerHandle<OffsetLayer> _at = LayerHandle<OffsetLayer>();

  @override
  bool get alwaysNeedsCompositing => true;

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    final OffsetLayer at = _at.layer ??= OffsetLayer();
    at.offset = offset;
    if (!identical(_frosts.parent, at)) {
      _frosts.remove();
      at.append(_frosts);
    }
    at.remove();
    context.addLayer(at);
  }

  @override
  void dispose() {
    _at.layer = null;
    super.dispose();
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

/// A coarse snapshot of a backdrop, [GlassBackdropState._ratio] pixels per
/// point, taken after drawn frame [frame] with the backdrop at [origin].
class _Snapshot {
  _Snapshot(this.frame, this.origin, this.width, this.height, this.data);

  final int frame;
  final Offset origin;
  final int width;
  final int height;
  final ByteData data;

  /// Mean luma over the pixels [area] (global logical) touches.
  double? meanLuma(Rect area) {
    const double ratio = GlassBackdropState._ratio;
    final Rect local = area.shift(-origin);
    final int x0 = (local.left * ratio).floor().clamp(0, width);
    final int x1 = (local.right * ratio).ceil().clamp(0, width);
    final int y0 = (local.top * ratio).floor().clamp(0, height);
    final int y1 = (local.bottom * ratio).ceil().clamp(0, height);
    // Premultiplied: what is see-through counts for as much as it covers
    // (a backdrop with no background of its own is not black).
    var sum = 0.0;
    var cover = 0.0;
    for (var y = y0; y < y1; y++) {
      for (var x = x0; x < x1; x++) {
        final int i = (y * width + x) * 4;
        sum +=
            0.2126 * data.getUint8(i) +
            0.7152 * data.getUint8(i + 1) +
            0.0722 * data.getUint8(i + 2);
        cover += data.getUint8(i + 3);
      }
    }
    return cover == 0 ? null : sum / cover;
  }
}
