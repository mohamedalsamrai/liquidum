// Comparison harness: Apple's native tab bar or Liquidum's, over the same
// background, driven by the same scripted touches (see ios/RunnerTests).
//
// `<tmp>/comparison.txt` holds "<apple|liquidum|none> <background> [flags]",
// flags being any of `log` (write liquidum's per-frame state), `view=<name>`
// (a GlassTabBarDebugView), `noshare` (the lens takes its own capture),
// `hold=<x>` (hold a press at x in the bar, for still comparisons), `bare`
// (no tab content), `optics=<mask>` (GlassTabBarOptics stages) and
// `lift=<progress>` (the optics at a fixed lift), `tint=<rrggbb>` and
// `utint=<rrggbb>` (selected and normal item colors) and `badge=<i>:<text>`
// (a badge on tab i), `count=<n>` (n tabs, up to five), `glass=`, `indicator=` and `lens=<rrggbbaa>` (glass
// tints).
//
// The bar and background are laid out as on the reference screen (the
// iPhone 17 Pro Max the bars were compared on): on any other screen the bar
// keeps its size, centered, and the background moves with it, so captures
// from different devices compare point for point.
//
// A marker in a clear band above the bar shows where the finger is, so each
// recorded frame can be measured against the finger. Below it, a 12-bit code
// gives the milliseconds since the touch began, on the frame clock the bar
// animates with, so frames can be matched to the animation's own time even
// when the simulator presents them late.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:liquidum/liquidum.dart';

import 'native_tab_bar.dart';
import 'sf_symbol.dart';
import 'tabs.dart';

/// The screen the bar was compared with UIKit's on, and the bar's margin
/// there.
const Size referenceScreen = Size(440, 956);
const double barMargin = 21;

/// Top of the marker band, measured up from the bottom of the screen.
const double markerBandBottom = 21 + 62 + 40;
const double markerBandHeight = 24;

/// Top of the clock code, measured down from the top of the reference screen.
const double clockTop = 838;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await GlassTabBar.precache();
  await SfSymbol.precache(tabs.map((TabSpec t) => t.symbol));
  final file = File('${Directory.systemTemp.path}/comparison.txt');
  final List<String> config = file.existsSync()
      ? file.readAsStringSync().trim().split(' ')
      : <String>['liquidum', 'gray'];
  final Set<String> flags = config.skip(2).toSet();
  if (flags.contains('log')) {
    _StateLog.start();
  }
  if (flags.contains('adaptlog')) {
    _AdaptLog.start();
  }
  final String? view = flags
      .where((String f) => f.startsWith('view='))
      .map((String f) => f.substring(5))
      .firstOrNull;
  final double? hold = flags
      .where((String f) => f.startsWith('hold='))
      .map((String f) => double.parse(f.substring(5)))
      .firstOrNull;
  _count = flags
      .where((String f) => f.startsWith('count='))
      .map((String f) => int.parse(f.substring(6)))
      .firstOrNull;
  runApp(
    ComparisonApp(
      apple: config[0] == 'apple',
      noBar: config[0] == 'none',
      hold: hold,
      bare: flags.contains('bare'),
      optics:
          flags
              .where((String f) => f.startsWith('optics='))
              .map((String f) => int.parse(f.substring(7)))
              .firstOrNull ??
          GlassTabBarOptics.all,
      lift: flags
          .where((String f) => f.startsWith('lift='))
          .map((String f) => double.parse(f.substring(5)))
          .firstOrNull,
      background: config[1],
      view: GlassTabBarDebugView.values.firstWhere(
        (GlassTabBarDebugView v) => v.name == view,
        orElse: () => GlassTabBarDebugView.none,
      ),
      shareBackdrop: !flags.contains('noshare'),
      tint: _color(flags, 'tint='),
      glass: _rgba(flags, 'glass='),
      indicator: _rgba(flags, 'indicator='),
      lens: _rgba(flags, 'lens='),
      unselectedTint: _color(flags, 'utint='),
      badges: <String?>[
        for (var i = 0; i < tabs.length; i++)
          flags
              .where((String f) => f.startsWith('badge=$i:'))
              .map((String f) => f.substring('badge=$i:'.length))
              .firstOrNull,
      ],
    ),
  );
}

// How many tabs to show (the `count=<n>` flag, up to five: the fifth is a
// search tab).
int? _count;
List<TabSpec> get _tabs => _count == null
    ? tabs
    : <TabSpec>[
        ...tabs,
        const TabSpec(
          icon: CupertinoIcons.search,
          label: 'Search',
          symbol: 'magnifyingglass',
        ),
      ].take(_count!).toList();

Color? _rgba(Set<String> flags, String prefix) =>
    flags.where((String f) => f.startsWith(prefix)).map((String f) {
      final int v = int.parse(f.substring(prefix.length), radix: 16);
      return Color((v & 0xff) << 24 | v >> 8);
    }).firstOrNull;

Color? _color(Set<String> flags, String prefix) => flags
    .where((String f) => f.startsWith(prefix))
    .map(
      (String f) =>
          Color(0xFF000000 | int.parse(f.substring(prefix.length), radix: 16)),
    )
    .firstOrNull;

/// Writes the appearance's inputs, as they change, to `<tmp>/liqadapt.txt`,
/// with the background changes (the `adaptlog` flag).
abstract final class _AdaptLog {
  static final List<String> lines = <String>[];
  static final Stopwatch _clock = Stopwatch()..start();
  static String _last = '';

  static String get _now =>
      (_clock.elapsedMicroseconds / 1e6).toStringAsFixed(4);

  static void mark(String text) => lines.add('$_now MARK $text');

  static void start() {
    final file = File('${Directory.systemTemp.path}/liqadapt.txt');
    GlassAppearance.debugOnChange = (GlassAppearance a, String event) {
      final (double black, double white, double fill, double gray) = a.face;
      final String text =
          'face ${black.toStringAsFixed(4)},${white.toStringAsFixed(4)} '
          'fill ${gray.toStringAsFixed(3)},${fill.toStringAsFixed(3)} '
          'icon ${a.isDark ? 'dark' : 'light'} '
          'pill ${a.pill.$1.toStringAsFixed(3)}';
      if (event != 'tick') {
        lines.add('$_now $event');
      }
      if (text != _last) {
        _last = text;
        lines.add('$_now $text');
      }
    };
    Timer.periodic(const Duration(seconds: 1), (_) {
      file.writeAsStringSync('${lines.join('\n')}\n');
    });
  }
}

/// Writes the bar's state every frame to `<tmp>/liqlog.txt`, in the format
/// of the UIKit log it is compared with (window coordinates; the bar sits at
/// x 21, y 873).
abstract final class _StateLog {
  static final List<String> _lines = <String>[];
  static final Offset _bar = Offset(
    barMargin,
    referenceScreen.height - barMargin - GlassTabBar.height,
  );

  static void start() {
    final file = File('${Directory.systemTemp.path}/liqlog.txt');
    if (file.existsSync()) {
      file.deleteSync();
    }
    GlassTabBarPhysics.debugOnTick = (GlassTabBarPhysics p, double now) {
      final Rect lens = p.lensRect.shift(_bar);
      final Rect platter = p.platterRect.shift(_bar);
      final Offset? touch = p.touch == null ? null : p.touch! + _bar;
      final double grow = 2 * GlassTabBarPhysics.liftOutset * p.lift;
      String f(double v) => v.toStringAsFixed(4);
      _lines.add(
        '${now.toStringAsFixed(4)} '
        'touch=${touch == null ? '-' : '${f(touch.dx)},${f(touch.dy)}'} '
        'lens=${f(lens.left)},${f(lens.top)},${f(lens.width)},${f(lens.height)}'
        '|b${f(p.pillWidth + grow)}x${f(p.pillHeight + grow)}'
        '|t${f(p.flexScale.width)},${f(p.flexScale.height)},${f(p.flexDrift)},0 '
        'platter=${f(platter.left)},${f(platter.top)},${f(platter.width)},${f(platter.height)}'
        '|b398x62|t1,1,0,0 '
        'lift=${f(p.liftProgress)}/${f(p.liftProgress)} '
        'sx=${f(p.flexScale.width)}/${f(p.flexScale.width)} '
        'sy=${f(p.flexScale.height)}/${f(p.flexScale.height)} '
        'dx=${f(p.flexDrift)}/${f(p.flexDrift)} dy=0/0 ty=0/0 '
        'm=${f(p.flex)} tr=0,0 '
        'press=${f(p.press)} glow=${p.glowCenter == null ? '-' : '${f(p.glowCenter!.dx + _bar.dx)},${f(p.glowSize)},${f(p.glowAlpha)}'}',
      );
    };
    Timer.periodic(const Duration(seconds: 1), (_) {
      if (_lines.isEmpty) {
        return;
      }
      file.writeAsStringSync('${_lines.join('\n')}\n', mode: FileMode.append);
      _lines.clear();
    });
  }
}

class ComparisonApp extends StatefulWidget {
  const ComparisonApp({
    super.key,
    required this.apple,
    this.noBar = false,
    required this.background,
    this.hold,
    this.bare = false,
    this.optics = GlassTabBarOptics.all,
    this.lift,
    this.view = GlassTabBarDebugView.none,
    this.shareBackdrop = true,
    this.tint,
    this.unselectedTint,
    this.badges = const <String?>[],
    this.glass,
    this.indicator,
    this.lens,
  });

  final bool apple;

  /// No bar at all, for native experiments over the bare background.
  final bool noBar;
  final double? hold;
  final bool bare;
  final int optics;
  final double? lift;
  final String background;
  final GlassTabBarDebugView view;
  final bool shareBackdrop;
  final Color? tint;
  final Color? unselectedTint;
  final List<String?> badges;
  final Color? glass;
  final Color? indicator;
  final Color? lens;

  @override
  State<ComparisonApp> createState() => _ComparisonAppState();
}

class _ComparisonAppState extends State<ComparisonApp>
    with SingleTickerProviderStateMixin {
  int _selected = 0;
  final ValueNotifier<Offset?> _finger = ValueNotifier<Offset?>(null);

  // Milliseconds since the touch began, on the frame clock: the first frame
  // after a touch counts as half a frame (8ms) in, as the bar's physics does.
  final ValueNotifier<int> _clockMs = ValueNotifier<int>(0);
  late final Ticker _clock = createTicker(_onClock);
  Duration? _touchFrame;
  bool _touchPending = false;

  void _onClock(Duration _) {
    final Duration now = SchedulerBinding.instance.currentFrameTimeStamp;
    if (_touchPending) {
      _touchPending = false;
      _touchFrame = now - const Duration(microseconds: 8333);
    }
    final Duration since = now - _touchFrame!;
    _clockMs.value = since.inMilliseconds.clamp(0, 4095);
    if (_finger.value == null && since > const Duration(seconds: 4)) {
      _clock.stop();
    }
  }

  // A background that steps through flat grays ("steps:<ms>:<hex>,<hex>,..."),
  // telling the native side (channel liquidum/marks) when each is shown.
  Timer? _steps;
  int _step = 0;
  static const _marks = MethodChannel('liquidum/marks');

  String get _background {
    final String kind = widget.background;
    if (kind.startsWith('seq:')) {
      // "seq:<ms>:<kind>|<kind>|...": any backgrounds, in turn.
      final List<String> kinds = kind.split(':')[2].split('|');
      return kinds[_step % kinds.length];
    }
    if (!kind.startsWith('steps:')) {
      return kind;
    }
    final List<String> values = kind.split(':')[2].split(',');
    return 'flat-${values[_step % values.length]}';
  }

  void _startSteps() {
    final List<String> parts = widget.background.split(':');
    final int count = parts[2].split(parts[0] == 'seq' ? '|' : ',').length;
    void mark() => SchedulerBinding.instance.addPostFrameCallback((_) {
      _AdaptLog.mark(_background);
      _marks.invokeMethod<void>('mark', _background).catchError((_) {});
    });
    mark();
    _steps = Timer.periodic(Duration(milliseconds: int.parse(parts[1])), (_) {
      if (_step + 1 >= count * 2) {
        _steps?.cancel();
        return;
      }
      setState(() => _step++);
      mark();
    });
  }

  @override
  void initState() {
    super.initState();
    // Sees every pointer, including those that go on to a platform view.
    GestureBinding.instance.pointerRouter.addGlobalRoute(_track);
    if (widget.background.startsWith('steps:') ||
        widget.background.startsWith('seq:')) {
      _startSteps();
    }
  }

  void _track(PointerEvent event) {
    if (event is PointerDownEvent) {
      _touchPending = true;
      if (!_clock.isActive) {
        _clock.start();
      }
    }
    if (event is PointerDownEvent || event is PointerMoveEvent) {
      _finger.value = event.position;
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      _finger.value = null;
    }
  }

  @override
  void dispose() {
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_track);
    _steps?.cancel();
    _clock.dispose();
    _clockMs.dispose();
    _finger.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoApp(
      debugShowCheckedModeBanner: false,
      home: Builder(builder: _buildHome),
    );
  }

  Widget _buildHome(BuildContext context) {
    final Size screen = MediaQuery.sizeOf(context);
    // Where the reference screen's origin lies on this one.
    final origin = Offset(
      (screen.width - referenceScreen.width) / 2,
      screen.height - referenceScreen.height,
    );
    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: GlassBackdrop(
            child: CustomPaint(painter: _Background(_background, origin)),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: markerBandBottom,
          height: markerBandHeight,
          child: CustomPaint(painter: _Marker(_finger)),
        ),
        Positioned(
          left: 0,
          top: origin.dy + clockTop,
          width: 4 + 12 * 8,
          height: 8,
          child: CustomPaint(painter: _ClockCode(_clockMs)),
        ),
        if (widget.apple)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: NativeTabBar.height,
            child: NativeTabBar(
              items: _tabs,
              selectedIndex: _selected,
              onSelected: (int i) => setState(() => _selected = i),
              tint: widget.tint,
              unselectedTint: widget.unselectedTint,
              badges: widget.badges,
            ),
          )
        else if (!widget.noBar)
          Positioned(
            left: origin.dx + barMargin,
            width: referenceScreen.width - 2 * barMargin,
            bottom: barMargin,
            // Centered: with up to three tabs the bar hugs them.
            child: Center(
              child: GlassTabBar(
                items: <GlassTabItem>[
                  for (var i = 0; i < _tabs.length; i++)
                    GlassTabItem(
                      icon: _tabs[i].glassItem.icon,
                      label: _tabs[i].label,
                      badge: i < widget.badges.length ? widget.badges[i] : null,
                    ),
                ],
                // UIKit ignores its unselected tint; so does the comparison.
                selectedColor: widget.tint,
                glassColor: widget.glass,
                indicatorColor: widget.indicator,
                lensColor: widget.lens,
                selectedIndex: _selected,
                onSelected: (int i) => setState(() => _selected = i),
                debugView: widget.view,
                debugShareBackdrop: widget.shareBackdrop,
                debugHold: widget.hold == null
                    ? null
                    : Offset(widget.hold!, 31),
                debugHideContent: widget.bare,
                debugOptics: widget.optics,
                debugLift: widget.lift,
                // Above the marker band and the clock code.
                debugInspector: const Rect.fromLTWH(0, -380, 398, 300),
              ),
            ),
          ),
      ],
    );
  }
}

/// White band with a black tick at the finger's x.
class _Marker extends CustomPainter {
  _Marker(this.finger) : super(repaint: finger);

  final ValueNotifier<Offset?> finger;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFFFFFFF),
    );
    final Offset? at = finger.value;
    if (at != null) {
      canvas.drawRect(
        Rect.fromLTWH(at.dx - 1, 0, 2, size.height),
        Paint()..color = const Color(0xFF000000),
      );
    }
  }

  @override
  bool shouldRepaint(_Marker oldDelegate) => false;
}

/// [value] in 12 bits, most significant first: a black 6×8pt block for each
/// set bit, every 8pt from x = 4.
class _ClockCode extends CustomPainter {
  _ClockCode(this.value) : super(repaint: value);

  final ValueNotifier<int> value;

  @override
  void paint(Canvas canvas, Size size) {
    for (var bit = 0; bit < 12; bit++) {
      if (value.value >> (11 - bit) & 1 == 1) {
        canvas.drawRect(
          Rect.fromLTWH(4.0 + bit * 8, 0, 6, 8),
          Paint()..color = const Color(0xFF000000),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_ClockCode oldDelegate) => false;
}

/// One of the calibration backgrounds, drawn in the reference screen's
/// coordinates with their origin at [origin].
class _Background extends CustomPainter {
  const _Background(this.kind, this.origin);

  final String kind;
  final Offset origin;

  static const _black = Color(0xFF000000);
  static const _white = Color(0xFFFFFFFF);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.translate(origin.dx, origin.dy);
    final double w = referenceScreen.width, h = referenceScreen.height;
    switch (kind) {
      case 'stripes':
        for (var i = 0; i < 44; i++) {
          canvas.drawRect(
            Rect.fromLTWH(i * w / 44, 0, w / 44, h),
            Paint()..color = i.isEven ? _black : _white,
          );
        }
      case 'hstripes':
        for (var y = 0.0; y < h; y += 20) {
          canvas.drawRect(Rect.fromLTWH(0, y, w, 10), Paint()..color = _black);
        }
      case 'grid':
        // Thin lines every 8pt, and every 40pt a colored one, so that
        // displaced lines can be told apart.
        canvas.drawColor(_white, BlendMode.src);
        for (var i = 0; i * 8.0 < w; i++) {
          canvas.drawRect(
            Rect.fromLTWH(i * 8.0, 0, 1, h),
            Paint()..color = i % 5 == 0 ? const Color(0xFFE0003A) : _black,
          );
        }
        for (var i = 0; i * 8.0 < h; i++) {
          canvas.drawRect(
            Rect.fromLTWH(0, i * 8.0, w, 1),
            Paint()..color = i % 5 == 0 ? const Color(0xFF0060E0) : _black,
          );
        }
      case 'rampx':
        canvas.drawRect(
          Offset.zero & referenceScreen,
          Paint()
            ..shader = ui.Gradient.linear(Offset.zero, Offset(w, 0), <Color>[
              _black,
              _white,
            ]),
        );
      case 'blocks':
        final int cols = (w / 40).ceil(), rows = (h / 40).ceil();
        for (var r = 0; r < rows; r++) {
          for (var c = 0; c < cols; c++) {
            final int i = r * cols + c;
            canvas.drawRect(
              Rect.fromLTWH(c * 40.0, r * 40.0, 40, 40),
              Paint()
                ..color = HSVColor.fromAHSV(
                  1,
                  (i * 47) % 360 * 1.0,
                  0.75,
                  0.95,
                ).toColor(),
            );
          }
        }
      case 'saw':
        // Position code: red rises over every 32pt in x, green over
        // every 32pt in y.
        canvas.drawRect(
          Offset.zero & referenceScreen,
          Paint()
            ..shader = ui.Gradient.linear(
              Offset.zero,
              const Offset(32, 0),
              const <Color>[Color(0xFF000000), Color(0xFFFF0000)],
              null,
              TileMode.repeated,
            ),
        );
        canvas.drawRect(
          Offset.zero & referenceScreen,
          Paint()
            ..blendMode = BlendMode.plus
            ..shader = ui.Gradient.linear(
              Offset.zero,
              const Offset(0, 32),
              const <Color>[Color(0xFF000000), Color(0xFF00FF00)],
              null,
              TileMode.repeated,
            ),
        );
      case 'vstripe8':
        canvas.drawColor(_white, BlendMode.src);
        for (var x = 0.0; x < w; x += 8) {
          canvas.drawRect(Rect.fromLTWH(x, 0, 4, h), Paint()..color = _black);
        }
      case 'hstripe8':
        canvas.drawColor(_white, BlendMode.src);
        for (var y = 0.0; y < h; y += 8) {
          canvas.drawRect(Rect.fromLTWH(0, y, w, 4), Paint()..color = _black);
        }
      case 'dark':
        canvas.drawColor(const Color(0xFF15171C), BlendMode.src);
      case 'white':
        canvas.drawColor(_white, BlendMode.src);
      case final String rects when rects.startsWith('rects-'):
        // "rects-<bg>-<fg>-<l>,<t>,<w>,<h>+...": rectangles on a flat color.
        final List<String> p = rects.split('-');
        canvas.drawColor(
          Color(0xFF000000 | int.parse(p[1], radix: 16)),
          BlendMode.src,
        );
        final paint = Paint()
          ..color = Color(0xFF000000 | int.parse(p[2], radix: 16));
        for (final String spec in p[3].split('+')) {
          final List<double> r = spec.split(',').map(double.parse).toList();
          canvas.drawRect(Rect.fromLTWH(r[0], r[1], r[2], r[3]), paint);
        }
      case final String rect when rect.startsWith('rect-'):
        // "rect-<bg>-<fg>-<l>,<t>,<w>,<h>": a rectangle on a flat color.
        final List<String> p = rect.split('-');
        final List<double> r = p[3].split(',').map(double.parse).toList();
        canvas
          ..drawColor(
            Color(0xFF000000 | int.parse(p[1], radix: 16)),
            BlendMode.src,
          )
          ..drawRect(
            Rect.fromLTWH(r[0], r[1], r[2], r[3]),
            Paint()..color = Color(0xFF000000 | int.parse(p[2], radix: 16)),
          );
      case final String flat when flat.startsWith('flat-'):
        canvas.drawColor(
          Color(0xFF000000 | int.parse(flat.substring(5), radix: 16)),
          BlendMode.src,
        );
      default:
        // A mid gray: glass edges, lens and shadow all show against it.
        canvas.drawColor(const Color(0xFF7F7F7F), BlendMode.src);
    }
  }

  @override
  bool shouldRepaint(_Background oldDelegate) =>
      oldDelegate.kind != kind || oldDelegate.origin != origin;
}
