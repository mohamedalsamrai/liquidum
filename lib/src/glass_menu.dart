part of 'glass.dart';

/// An item in a glass menu (UIKit's `UIAction` in a `UIMenu`): a row with a
/// [label], an optional [icon] before it, and a checkmark when [checked].
///
/// ```dart
/// GlassButton(
///   label: 'Sort',
///   menu: [
///     GlassMenuItem(label: 'Name', checked: true, onPressed: byName),
///     GlassMenuItem(label: 'Date', onPressed: byDate),
///     GlassMenuItem.divider(),
///     GlassMenuItem(label: 'Delete', icon: CupertinoIcons.trash,
///         destructive: true, onPressed: delete),
///   ],
/// )
/// ```
@immutable
class GlassMenuItem {
  const GlassMenuItem({
    required String this.label,
    this.icon,
    this.onPressed,
    this.destructive = false,
    this.checked = false,
  }) : items = null,
       _divider = false;

  /// A line between groups of items, as between UIKit's inline menus.
  const GlassMenuItem.divider()
    : label = null,
      icon = null,
      onPressed = null,
      destructive = false,
      checked = false,
      items = null,
      _divider = true;

  /// A row that opens [items] (UIKit's nested `UIMenu`), with a chevron.
  const GlassMenuItem.submenu({
    required String this.label,
    this.icon,
    required List<GlassMenuItem> this.items,
  }) : onPressed = null,
       destructive = false,
       checked = false,
       _divider = false;

  final String? label;
  final IconData? icon;

  /// Called when the item is chosen (the menu closes); null disables it.
  final VoidCallback? onPressed;

  /// Shown in red, as UIKit's destructive actions.
  final bool destructive;

  /// Shows a checkmark before the item (UIKit's `state = .on`).
  final bool checked;

  /// A submenu's items.
  final List<GlassMenuItem>? items;

  final bool _divider;

  /// Whether this is a [GlassMenuItem.divider].
  bool get isDivider => _divider;
}

/// UIKit's menu metrics (iOS 26.5): a 250pt platter of large regular glass
/// with continuous corners of 34pt; rows 42pt tall, 10pt from the top and
/// bottom; groups 21pt apart with a hairline between them.
abstract final class _MenuMetrics {
  static const double width = 250;
  static const double radius = 34;
  static const double row = 42;
  static const double pad = 10;
  static const double groupGap = 21;
  static const double dividerInset = 24;

  // Within a row: the checkmark's left edge, an icon's center, the label's
  // start with and without icons, and the submenu chevron's left edge.
  static const double check = 21;
  static const double iconCenter = 55.17;
  static const double labelWithIcons = 79;
  static const double label = 28;
  static const double chevron = 214;
  static const double labelEnd = 28;

  // A submenu's header: its height, and its turned chevron's left edge.
  static const double header = 62;
  static const double chevronDown = 212.67;

  /// The groups of rows, without the dividers.
  static List<List<GlassMenuItem>> groups(List<GlassMenuItem> items) {
    final List<List<GlassMenuItem>> out = <List<GlassMenuItem>>[
      <GlassMenuItem>[],
    ];
    for (final GlassMenuItem item in items) {
      if (item.isDivider) {
        if (out.last.isNotEmpty) {
          out.add(<GlassMenuItem>[]);
        }
      } else {
        out.last.add(item);
      }
    }
    if (out.last.isEmpty && out.length > 1) {
      out.removeLast();
    }
    return out;
  }

  static double height(List<List<GlassMenuItem>> groups) {
    final int rows = groups.fold(
      0,
      (int n, List<GlassMenuItem> g) => n + g.length,
    );
    return 2 * pad + rows * row + (groups.length - 1) * groupGap;
  }
}

/// The springs of UIKit's liquid morph (`_UILiquidMorphAnimation`), fitted
/// to its frames on iOS 26.5: one progress drives the source shrinking and
/// the menu growing; the menu's vertical center has its own spring with a
/// kick along its growth, so it sags past its place and settles.
abstract final class _MorphSprings {
  // Progress: omega 18.1, damping ratio 0.75 opening; 12.85 and 0.80
  // closing.
  static const double openResponse = 2 * math.pi / 18.1;
  static const double openDamping = 0.75;
  static const double closeResponse = 2 * math.pi / 12.85;
  static const double closeDamping = 0.80;

  // The vertical center: omega 18 and 0.6 opening, with a kick of 10 times
  // the height the menu gains (points per second); 16.3 and 0.82 closing,
  // with 520 plus 5.8 times the height it loses.
  static const double openYResponse = 2 * math.pi / 18;
  static const double openYDamping = 0.6;
  static const double closeYResponse = 2 * math.pi / 16.3;
  static const double closeYDamping = 0.82;

  // The source capsule narrows to a circle on a stiffer, critically damped
  // spring.
  static const double narrowResponse = 2 * math.pi / 28;

  /// How far the source shrinks (and travels toward the menu's center).
  static const double sourceEnd = 0.25;

  /// How deep the menu's content is blurred at the start (points), and
  /// once the menu is closing.
  static const double blur = 8;
  static const double closeBlur = 12;

  // A submenu opening or closing: omega 15.86, damping ratio 0.853.
  static const double submenuResponse = 2 * math.pi / 15.86;
  static const double submenuDamping = 0.853;

  /// How close the two shapes must come to melt (points).
  static const double spacing = 20;
}

/// Presses a menu's glass with a finger that went down elsewhere (on the
/// button that opened the menu) and slid onto it, as UIKit's menu leans
/// toward and glows under that finger. Global coordinates.
class _GlassPressFeed {
  _GlassState? _glass;
  bool _down = false;

  void move(Offset global) {
    final _GlassState? glass = _glass;
    if (glass == null) {
      return;
    }
    if (!_down) {
      _down = true;
      glass._fedDown(global);
    } else {
      glass._fedMove(global);
    }
  }

  void up() {
    if (_down) {
      _down = false;
      _glass?._fedUp();
    }
  }
}

/// Opens [items] in a glass menu that grows out of [source] (the box of the
/// widget at [context]) with UIKit's liquid morph. [sourceContent] is drawn
/// on the source's glass while it shrinks away; [onClosed] runs once the
/// menu has morphed back into the source.
GlobalKey<_GlassMenuOverlayState> _showGlassMenu({
  required BuildContext context,
  required List<GlassMenuItem> items,
  required Widget sourceContent,
  required VoidCallback onClosed,
}) {
  final OverlayState overlay = Overlay.of(context, rootOverlay: true);
  final RenderBox box = context.findRenderObject()! as RenderBox;
  final RenderBox overlayBox = overlay.context.findRenderObject()! as RenderBox;
  final Rect source = MatrixUtils.transformRect(
    box.getTransformTo(overlayBox),
    Offset.zero & box.size,
  );
  final GlobalKey<_GlassMenuOverlayState> key =
      GlobalKey<_GlassMenuOverlayState>();
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (BuildContext context) => _GlassMenuOverlay(
      key: key,
      source: source,
      items: items,
      sourceContent: sourceContent,
      onClosed: () {
        entry.remove();
        entry.dispose();
        onClosed();
      },
    ),
  );
  overlay.insert(entry);
  return key;
}

class _GlassMenuOverlay extends StatefulWidget {
  const _GlassMenuOverlay({
    super.key,
    required this.source,
    required this.items,
    required this.sourceContent,
    required this.onClosed,
  });

  final Rect source;
  final List<GlassMenuItem> items;
  final Widget sourceContent;
  final VoidCallback onClosed;

  @override
  State<_GlassMenuOverlay> createState() => _GlassMenuOverlayState();
}

class _GlassMenuOverlayState extends State<_GlassMenuOverlay>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  final GlassSpring _progress = GlassSpring(
    response: _MorphSprings.openResponse,
    dampingRatio: _MorphSprings.openDamping,
    tolerance: 2e-4,
  );
  final GlassSpring _narrow = GlassSpring(
    response: _MorphSprings.narrowResponse,
    dampingRatio: 1,
  );
  // Settled within a twentieth of a point (and a point a second): finer
  // than a pixel, so the menu stops drawing once it looks still.
  final GlassSpring _y = GlassSpring(
    response: _MorphSprings.openYResponse,
    dampingRatio: _MorphSprings.openYDamping,
    tolerance: 0.05,
  );
  Duration? _last;
  bool _closing = false;
  Rect? _menu;
  bool _up = false;
  List<List<GlassMenuItem>> _groups = const <List<GlassMenuItem>>[];
  GlassMenuItem? _highlight;
  final _GlassPressFeed _feed = _GlassPressFeed();

  // An open submenu: its item, the row it grew from, and how far it is
  // open (UIKit's: it grows out of the row's highlight over the menu,
  // which recedes to 0.97 and dims).
  GlassMenuItem? _sub;
  Rect _subRow = Rect.zero;
  Rect _subStart = Rect.zero;
  final GlassSpring _subSpring = GlassSpring(
    response: _MorphSprings.submenuResponse,
    dampingRatio: _MorphSprings.submenuDamping,
  );

  // The rows' boxes in the overlay, where the menu settles.
  Iterable<(Rect, GlassMenuItem)> _rows() sync* {
    final Rect? menu = _menu;
    if (menu == null) {
      return;
    }
    var y = menu.top + _MenuMetrics.pad;
    for (var g = 0; g < _groups.length; g++) {
      if (g > 0) {
        y += _MenuMetrics.groupGap;
      }
      for (final GlassMenuItem item in _groups[g]) {
        yield (Rect.fromLTWH(menu.left, y, menu.width, _MenuMetrics.row), item);
        y += _MenuMetrics.row;
      }
    }
  }

  GlassMenuItem? _rowAt(Offset position) {
    for (final (Rect box, GlassMenuItem item) in _rows()) {
      if (box.contains(position)) {
        return _enabled(item) ? item : null;
      }
    }
    return null;
  }

  static bool _enabled(GlassMenuItem item) =>
      item.onPressed != null || item.items != null;

  /// A finger that opened the menu from its source moved to [position]
  /// (overlay coordinates): the row under it highlights, as UIKit's.
  void track(Offset position) {
    if (_closing) {
      return;
    }
    final GlassMenuItem? row = _rowAt(position);
    if (row != _highlight) {
      setState(() => _highlight = row);
    }
    final RenderObject? box = context.findRenderObject();
    if (box is RenderBox && position.isFinite) {
      _feed.move(box.localToGlobal(position));
    } else {
      _feed.up();
    }
  }

  /// That finger lifted at [position] after dragging: the row under it is
  /// chosen; off the menu, the menu stays open.
  void release(Offset position) {
    final GlassMenuItem? row = _rowAt(position);
    _feed.up();
    setState(() => _highlight = null);
    if (row != null) {
      _choose(row);
    }
  }

  @override
  void initState() {
    super.initState();
    _progress.target = 1;
    _narrow.target = 1;
    _ticker.start();
  }

  // Where the menu goes: from the source's top corner down, or from its
  // bottom corner up when it would not fit below (its rows reversed, as
  // UIKit's); from its left edge, or its right edge near the screen's
  // right.
  Rect _place(Size screen, EdgeInsets safe, double height) {
    final Rect s = widget.source;
    const double margin = 8;
    double left = s.left;
    if (left + _MenuMetrics.width > screen.width - margin) {
      left = s.right - _MenuMetrics.width;
    }
    left = left.clamp(
      margin,
      math.max(margin, screen.width - margin - _MenuMetrics.width),
    );
    double top = s.top;
    _up = false;
    if (top + height > screen.height - safe.bottom - margin &&
        s.bottom - height >= safe.top + margin) {
      top = s.bottom - height;
      _up = true;
    }
    // Clear of the screen's insets by a margin, but never away from a
    // source that sits nearer (a bar item at the bar's top).
    final double topLimit = math.min(safe.top + margin, s.top);
    final double bottomLimit = math.max(
      screen.height - safe.bottom - margin,
      s.bottom,
    );
    top = top.clamp(topLimit, math.max(topLimit, bottomLimit - height));
    return Rect.fromLTWH(left, top, _MenuMetrics.width, height);
  }

  void _start(Rect menu) {
    final Rect s = widget.source;
    final double gain = menu.height - s.height / 2;
    final double dir = menu.center.dy >= s.center.dy ? 1 : -1;
    _y
      ..snap(s.center.dy)
      ..target = menu.center.dy
      ..velocity = dir * 10 * gain;
  }

  void close() {
    if (_closing) {
      return;
    }
    final Rect? menu = _menu;
    if (menu == null) {
      widget.onClosed();
      return;
    }
    _closing = true;
    // An open submenu folds back as the menu morphs away.
    _subSpring.target = 0;
    final Rect s = widget.source;
    final double loss = menu.height - s.height / 2;
    final double dir = menu.center.dy >= s.center.dy ? 1 : -1;
    _progress
      ..configure(_MorphSprings.closeResponse, _MorphSprings.closeDamping)
      ..target = 0;
    _narrow.target = 0;
    _y
      ..configure(_MorphSprings.closeYResponse, _MorphSprings.closeYDamping)
      ..target = s.center.dy
      ..velocity += dir * (520 + 5.8 * loss);
    _wake();
  }

  void _wake() {
    if (!_ticker.isActive) {
      _last = null;
      _ticker.start();
    }
  }

  void _tick(Duration elapsed) {
    final double dt = _last == null
        ? 1 / 60
        : (elapsed - _last!).inMicroseconds / 1e6;
    _last = elapsed;
    _progress.step(dt);
    _narrow.step(dt);
    _y.step(dt);
    _subSpring.step(dt);
    if (_sub != null && _subSpring.target == 0 && _subSpring.isSettled) {
      _sub = null;
    }
    if (_progress.isSettled &&
        _narrow.isSettled &&
        _y.isSettled &&
        _subSpring.isSettled) {
      _ticker.stop();
      _last = null;
      if (_closing) {
        widget.onClosed();
        return;
      }
    }
    setState(() {});
  }

  void _choose(GlassMenuItem item) {
    if (_closing) {
      return;
    }
    if (item.items != null) {
      _openSub(item);
      return;
    }
    item.onPressed?.call();
    close();
  }

  void _openSub(GlassMenuItem item) {
    // The row where the menu will have receded to (0.97 from its top
    // corner), as UIKit places the submenu.
    final Rect menu = _menu!;
    for (final (Rect box, GlassMenuItem row) in _rows()) {
      if (identical(row, item)) {
        // It grows out of the row's highlight: 10pt in from either side.
        _subStart = Rect.fromLTRB(
          box.left + 10,
          box.top,
          box.right - 10,
          box.bottom,
        );
        _subRow = Rect.fromLTWH(
          menu.left + (box.left - menu.left) * 0.97,
          menu.top + (box.top - menu.top) * 0.97,
          box.width * 0.97,
          box.height * 0.97,
        );
      }
    }
    setState(() {
      _sub = item;
      _highlight = null;
    });
    _subSpring.target = 1;
    _wake();
  }

  void _closeSub() {
    setState(() => _highlight = null);
    _subSpring.target = 0;
    _wake();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final MediaQueryData media = MediaQuery.of(context);
    final List<List<GlassMenuItem>> groups = _MenuMetrics.groups(widget.items);
    final double height = _MenuMetrics.height(groups);
    if (_menu == null) {
      _menu = _place(media.size, media.padding, height);
      _start(_menu!);
      _groups = _up
          ? groups.reversed
                .map((List<GlassMenuItem> g) => g.reversed.toList())
                .toList()
          : groups;
    }
    final Rect menu = _menu!;
    final Rect s = widget.source;
    final double p = _progress.value;
    final bool dark = media.platformBrightness == Brightness.dark;

    // The source: shrinks to a quarter, a quarter of the way to the
    // menu's center, its capsule narrowing to a circle.
    final double ks = 1 + (_MorphSprings.sourceEnd - 1) * p;
    final double sw = ui.lerpDouble(s.width, s.height, _narrow.value)!;
    final Offset sc =
        s.center + (menu.center - s.center) * (_MorphSprings.sourceEnd * p);
    final Rect sourceRect = Rect.fromCenter(
      center: sc,
      width: math.max(sw * ks, 0),
      height: math.max(s.height * ks, 0),
    );

    // The menu: from a circle half the source's height across, at the
    // source's center, to its place; its height from its width's to its
    // own, its corners from round to 34pt.
    final double k0 = (s.height / 2) / _MenuMetrics.width;
    final double km = k0 + (1 - k0) * p;
    final double bh = ui.lerpDouble(_MenuMetrics.width, menu.height, p)!;
    // Round until about halfway, then its own corners (UIKit's blob stays
    // a circle longer than a linear change of the corners).
    final double pc = p.clamp(0.0, 1.0);
    final double radius =
        km *
        ui.lerpDouble(_MenuMetrics.width / 2, _MenuMetrics.radius, pc * pc)!;
    // Under an open submenu the menu recedes to 0.97 from its top corner
    // and dims.
    final double q = _sub == null ? 0 : _subSpring.value;
    final double recede = 1 - 0.03 * q;
    final Rect morphRect = Rect.fromCenter(
      center: Offset(ui.lerpDouble(s.center.dx, menu.center.dx, p)!, _y.value),
      width: math.max(_MenuMetrics.width * km, 0),
      height: math.max(bh * km, 0),
    );
    final Rect menuRect = Rect.fromLTWH(
      morphRect.left,
      morphRect.top,
      morphRect.width * recede,
      morphRect.height * recede,
    );
    final double shown = p.clamp(0.0, 1.0);

    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: close,
          ),
        ),
        GlassGroup(
          spacing: _MorphSprings.spacing,
          brightness: media.platformBrightness,
          child: Stack(
            children: <Widget>[
              if (p < 0.999 || _closing)
                Positioned.fromRect(
                  rect: sourceRect,
                  child: Glass(
                    child: Opacity(
                      opacity: (1 - shown),
                      child: Center(
                        child: Transform.scale(
                          scale: ks,
                          child: OverflowBox(
                            maxWidth: s.width,
                            maxHeight: s.height,
                            child: SizedBox(
                              width: s.width,
                              height: s.height,
                              child: widget.sourceContent,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              Positioned.fromRect(
                rect: menuRect,
                child: Glass._fed(
                  _feed,
                  radius: radius,
                  brightness: null,
                  interactive: !_closing,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(radius),
                    child: OverflowBox(
                      alignment: Alignment.topCenter,
                      maxWidth: double.infinity,
                      maxHeight: double.infinity,
                      child: Transform.scale(
                        scale: km * recede,
                        alignment: Alignment.topCenter,
                        child: _blurred(
                          shown,
                          SizedBox(
                            width: _MenuMetrics.width,
                            height: menu.height,
                            child: _sub != null
                                ? GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: _closeSub,
                                    child: Opacity(
                                      opacity: 1 - 0.55 * q.clamp(0.0, 1.0),
                                      child: IgnorePointer(
                                        child: _GlassMenuList(
                                          groups: _groups,
                                          dark: dark,
                                          hidden: _sub,
                                          highlight: null,
                                          onHighlight: (_) {},
                                          onChoose: (_) {},
                                        ),
                                      ),
                                    ),
                                  )
                                : IgnorePointer(
                                    ignoring: _closing || p < 0.5,
                                    child: _GlassMenuList(
                                      groups: _groups,
                                      dark: dark,
                                      highlight: _highlight,
                                      onHighlight: (GlassMenuItem? item) =>
                                          setState(() => _highlight = item),
                                      onChoose: _choose,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_sub != null) _submenu(media, dark, q),
      ],
    );
  }

  // A submenu: its own platter over the menu, with a 62pt header (its
  // label, semibold, and a chevron turned down) centered on the row it
  // came from, a hairline, and its rows; it grows out of the row's
  // highlight.
  Widget _submenu(MediaQueryData media, bool dark, double q) {
    final GlassMenuItem item = _sub!;
    final List<List<GlassMenuItem>> groups = _MenuMetrics.groups(item.items!);
    final double height = _MenuMetrics.header + _MenuMetrics.height(groups);
    double top = _subRow.center.dy - _MenuMetrics.header / 2;
    top = math.min(top, media.size.height - media.padding.bottom - 8 - height);
    top = math.max(top, media.padding.top + 8);
    final Rect end = Rect.fromLTWH(
      _menu!.left,
      top,
      _MenuMetrics.width,
      height,
    );
    final Rect start = _subStart;
    final Rect rect = Rect.lerp(start, end, q)!;
    final double radius = math.min(
      ui.lerpDouble(
        _MenuMetrics.row / 2,
        _MenuMetrics.radius,
        q.clamp(0.0, 1.0),
      )!,
      rect.shortestSide / 2,
    );
    final bool icons = groups.any(
      (List<GlassMenuItem> g) => g.any((GlassMenuItem i) => i.icon != null),
    );
    final Color color = dark
        ? const Color(0xF5FFFFFF)
        : const Color(0xF5000000);
    final Color divider = dark
        ? const Color(0x14FFFFFF)
        : const Color(0x14000000);
    return Positioned.fromRect(
      rect: rect,
      child: Glass(
        radius: radius,
        brightness: media.platformBrightness,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: OverflowBox(
            alignment: Alignment.topLeft,
            maxWidth: double.infinity,
            maxHeight: double.infinity,
            child: Opacity(
              opacity: (q * 2).clamp(0.0, 1.0),
              child: SizedBox(
                width: _MenuMetrics.width,
                height: height,
                child: Column(
                  children: <Widget>[
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _closeSub,
                      child: SizedBox(
                        height: _MenuMetrics.header,
                        child: Stack(
                          children: <Widget>[
                            Positioned(
                              left: icons
                                  ? _MenuMetrics.labelWithIcons
                                  : _MenuMetrics.label,
                              right: _MenuMetrics.labelEnd,
                              top: 0,
                              bottom: 0,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  item.label ?? '',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: -0.43,
                                    color: color,
                                    decoration: TextDecoration.none,
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              left: _MenuMetrics.dividerInset,
                              right: _MenuMetrics.dividerInset,
                              bottom: 0,
                              height: 1,
                              child: ColoredBox(color: divider),
                            ),
                            Positioned(
                              left: _MenuMetrics.chevronDown,
                              top: 0,
                              bottom: 0,
                              child: Center(
                                child: CustomPaint(
                                  size: const Size(12.67, 9.33),
                                  painter: _MenuGlyphPainter(
                                    _MenuGlyph.chevronDown,
                                    color,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    _GlassMenuList(
                      groups: groups,
                      dark: dark,
                      highlight: _highlight,
                      onHighlight: (GlassMenuItem? i) =>
                          setState(() => _highlight = i),
                      onChoose: _choose,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // The menu's content fades in through a blur, as UIKit's crossfade; when
  // the menu closes, the blur deepens at once (it is gone by the time the
  // platter has shrunk a tenth).
  Widget _blurred(double shown, Widget child) {
    final double sigma = _closing
        ? _MorphSprings.closeBlur * math.min(1, (1 - shown) * 10)
        : _MorphSprings.blur * (1 - shown);
    Widget out = child;
    if (sigma > 0.05) {
      out = ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: out,
      );
    }
    if (shown < 1) {
      out = Opacity(opacity: shown, child: out);
    }
    return out;
  }
}

/// A menu's rows, laid out as UIKit's.
class _GlassMenuList extends StatelessWidget {
  const _GlassMenuList({
    required this.groups,
    required this.dark,
    this.hidden,
    required this.highlight,
    required this.onHighlight,
    required this.onChoose,
  });

  final List<List<GlassMenuItem>> groups;
  final bool dark;

  /// A row left blank: the one an open submenu covers.
  final GlassMenuItem? hidden;
  final GlassMenuItem? highlight;
  final ValueChanged<GlassMenuItem?> onHighlight;
  final ValueChanged<GlassMenuItem> onChoose;

  @override
  Widget build(BuildContext context) {
    final bool icons = groups.any(
      (List<GlassMenuItem> g) => g.any((GlassMenuItem i) => i.icon != null),
    );
    final bool checks = groups.any(
      (List<GlassMenuItem> g) => g.any((GlassMenuItem i) => i.checked),
    );
    final Color divider = dark
        ? const Color(0x14FFFFFF)
        : const Color(0x14000000);
    final List<Widget> children = <Widget>[
      const SizedBox(height: _MenuMetrics.pad),
    ];
    for (var g = 0; g < groups.length; g++) {
      if (g > 0) {
        children.add(
          SizedBox(
            height: _MenuMetrics.groupGap,
            child: Center(
              child: Container(
                height: 1,
                margin: const EdgeInsets.symmetric(
                  horizontal: _MenuMetrics.dividerInset,
                ),
                color: divider,
              ),
            ),
          ),
        );
      }
      for (final GlassMenuItem item in groups[g]) {
        if (identical(item, hidden)) {
          children.add(const SizedBox(height: _MenuMetrics.row));
          continue;
        }
        children.add(
          _GlassMenuRow(
            item: item,
            icons: icons,
            checks: checks,
            dark: dark,
            highlighted: identical(item, highlight),
            onHighlight: onHighlight,
            onChoose: onChoose,
          ),
        );
      }
    }
    return Column(mainAxisSize: MainAxisSize.min, children: children);
  }
}

class _GlassMenuRow extends StatelessWidget {
  const _GlassMenuRow({
    required this.item,
    required this.icons,
    required this.checks,
    required this.dark,
    required this.highlighted,
    required this.onHighlight,
    required this.onChoose,
  });

  final GlassMenuItem item;
  final bool icons;
  final bool checks;
  final bool dark;
  final bool highlighted;
  final ValueChanged<GlassMenuItem?> onHighlight;
  final ValueChanged<GlassMenuItem> onChoose;

  @override
  Widget build(BuildContext context) {
    final bool enabled = item.onPressed != null || item.items != null;
    final Color base = dark ? const Color(0xF5FFFFFF) : const Color(0xF5000000);
    final Color color = !enabled
        ? base.withValues(alpha: 0.3)
        : item.destructive
        ? GlassTabBarStyle.resolve(GlassTabBarStyle.systemRed, dark: dark)
        : base;
    final double labelStart = icons
        ? _MenuMetrics.labelWithIcons
        : checks
        ? _MenuMetrics.iconCenter - 11
        : _MenuMetrics.label;
    final TextStyle style = TextStyle(
      fontSize: 17,
      fontWeight: FontWeight.w400,
      letterSpacing: -0.43,
      color: color,
      decoration: TextDecoration.none,
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => onHighlight(item) : null,
      onTapCancel: () => onHighlight(null),
      onTapUp: enabled ? (_) => onHighlight(null) : null,
      onTap: enabled ? () => onChoose(item) : null,
      child: Semantics(
        button: true,
        enabled: enabled,
        selected: item.checked,
        label: item.label,
        child: SizedBox(
          height: _MenuMetrics.row,
          width: _MenuMetrics.width,
          child: Stack(
            children: <Widget>[
              // UIKit's highlight: a capsule 10pt in from the platter's
              // sides, of vibrant white (approximated by a light wash).
              if (highlighted)
                Positioned.fill(
                  left: 10,
                  right: 10,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: dark
                          ? const Color(0x24FFFFFF)
                          : const Color(0x14000000),
                      borderRadius: BorderRadius.circular(_MenuMetrics.row / 2),
                    ),
                  ),
                ),
              if (item.checked)
                Positioned(
                  left: _MenuMetrics.check,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: CustomPaint(
                      size: const Size(13.33, 12.33),
                      painter: _MenuGlyphPainter(_MenuGlyph.check, color),
                    ),
                  ),
                ),
              if (item.icon != null)
                Positioned(
                  left: _MenuMetrics.iconCenter - 12,
                  width: 24,
                  top: 0,
                  bottom: 0,
                  child: Center(child: Icon(item.icon, size: 21, color: color)),
                ),
              Positioned(
                left: labelStart,
                right: _MenuMetrics.labelEnd,
                top: 0,
                bottom: 0,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    item.label ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: style,
                  ),
                ),
              ),
              if (item.items != null)
                Positioned(
                  left: _MenuMetrics.chevron,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: CustomPaint(
                      size: const Size(9.33, 12.67),
                      painter: _MenuGlyphPainter(_MenuGlyph.chevron, color),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _MenuGlyph { check, chevron, chevronDown }

class _MenuGlyphPainter extends CustomPainter {
  const _MenuGlyphPainter(this.glyph, this.color);

  final _MenuGlyph glyph;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // UIKit's glyphs (SF Symbols, subheadline semibold small): strokes of
    // about 1.6pt for the checkmark and 1.8pt for the chevron.
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = glyph == _MenuGlyph.check ? 1.6 : 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final double w = size.width, h = size.height;
    final Path path = switch (glyph) {
      _MenuGlyph.check =>
        Path()
          ..moveTo(1, h * 0.56)
          ..lineTo(w * 0.36, h - 1)
          ..lineTo(w - 1, 1),
      _MenuGlyph.chevron =>
        Path()
          ..moveTo(2, 1)
          ..lineTo(w - 2, h / 2)
          ..lineTo(2, h - 1),
      _MenuGlyph.chevronDown =>
        Path()
          ..moveTo(1, 2)
          ..lineTo(w / 2, h - 2)
          ..lineTo(w - 1, 2),
    };
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_MenuGlyphPainter old) =>
      old.glyph != glyph || old.color != color;
}

/// The source of a glass menu: [child] (a glass button or a bar item's
/// glass) opens [items] in a menu that grows out of it, as UIKit's. With
/// [longPress] false, as buttons that show their menu as their primary
/// action: the menu opens on touch down, and a finger that slides onto a
/// row highlights it and chooses it when lifted. With [longPress] true, as
/// the back button's history: the menu opens once the finger has held
/// still for 0.6s, and lifting it on a row chooses that row; a shorter
/// touch is [child]'s own tap. While its menu is open the source hides
/// (its glass at once, even in a [GlassGroup]): the menu morphs out of it
/// and back into it. [sourceContent] is drawn on the source's glass while
/// it shrinks away. For Liquidum's bars; not exported.
class GlassMenuAnchor extends StatefulWidget {
  const GlassMenuAnchor({
    super.key,
    required this.items,
    required this.sourceContent,
    this.longPress = false,
    required this.child,
  });

  /// The menu's items, asked for each time it opens.
  final List<GlassMenuItem> Function() items;
  final Widget sourceContent;
  final bool longPress;
  final Widget child;

  /// How long UIKit's back button is held before its history opens.
  static const Duration longPressDelay = Duration(milliseconds: 600);

  @override
  State<GlassMenuAnchor> createState() => _GlassMenuAnchorState();
}

class _GlassMenuAnchorState extends State<GlassMenuAnchor> {
  GlobalKey<_GlassMenuOverlayState>? _menu;
  int? _pointer;
  Offset _downAt = Offset.zero;
  bool _dragged = false;
  // Whether the finger that opened the menu chooses where it lifts (after
  // a long press, as UIKit's), or only after sliding.
  bool _liftChooses = false;

  // How far a finger must slide before lifting it chooses a row (or before
  // it stops being a long press).
  static const double _slop = 10;

  Offset _toOverlay(Offset global) {
    final RenderObject? box = _menu?.currentContext?.findRenderObject();
    return box is RenderBox ? box.globalToLocal(global) : global;
  }

  void _open() {
    if (_menu != null || !mounted) {
      return;
    }
    final List<GlassMenuItem> items = widget.items();
    if (items.isEmpty) {
      return;
    }
    setState(() {
      _menu = _showGlassMenu(
        context: context,
        items: items,
        sourceContent: widget.sourceContent,
        onClosed: () {
          if (mounted) {
            setState(() => _menu = null);
          }
        },
      );
    });
  }

  void _down(PointerDownEvent event) {
    if (_menu != null || widget.longPress) {
      return;
    }
    _pointer = event.pointer;
    _downAt = event.position;
    _dragged = false;
    _liftChooses = false;
    _open();
  }

  void _move(PointerMoveEvent event) {
    if (event.pointer != _pointer) {
      return;
    }
    if ((event.position - _downAt).distance > _slop) {
      _dragged = true;
    }
    if (_dragged || _liftChooses) {
      _menu?.currentState?.track(_toOverlay(event.position));
    }
  }

  void _up(PointerUpEvent event) {
    if (event.pointer != _pointer) {
      return;
    }
    _pointer = null;
    if (_dragged || _liftChooses) {
      _menu?.currentState?.release(_toOverlay(event.position));
    }
  }

  void _cancel(PointerCancelEvent event) {
    if (event.pointer == _pointer) {
      _pointer = null;
      _menu?.currentState?.track(Offset.infinite);
    }
  }

  void _longPressed(LongPressStartDetails details) {
    _pointer = -1;
    _downAt = details.globalPosition;
    _dragged = false;
    _liftChooses = true;
    _open();
    _menu?.currentState?.track(Offset.infinite);
  }

  @override
  Widget build(BuildContext context) {
    final bool open = _menu != null;
    Widget child = _GlassHiddenScope(
      hidden: open,
      child: _Hidden(hidden: open, child: widget.child),
    );
    if (widget.longPress) {
      // A long press wins over the child's tap; its moves and lift go to
      // the menu.
      return RawGestureDetector(
        behavior: HitTestBehavior.translucent,
        gestures: <Type, GestureRecognizerFactory>{
          LongPressGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
                () => LongPressGestureRecognizer(
                  duration: GlassMenuAnchor.longPressDelay,
                ),
                (LongPressGestureRecognizer r) {
                  r
                    ..onLongPressStart = _longPressed
                    ..onLongPressMoveUpdate = (LongPressMoveUpdateDetails d) {
                      _menu?.currentState?.track(_toOverlay(d.globalPosition));
                    }
                    ..onLongPressEnd = (LongPressEndDetails d) {
                      _pointer = null;
                      _menu?.currentState?.release(
                        _toOverlay(d.globalPosition),
                      );
                    };
                },
              ),
        },
        child: child,
      );
    }
    child = Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: _up,
      onPointerCancel: _cancel,
      child: child,
    );
    return child;
  }
}

/// Skips painting [child] while [hidden], keeping its layout and hit
/// testing. Unlike an [Opacity], it adds no layer: glass under a layer stops
/// sharing its screen reads with the glass beside it (see GlassBackdrop).
class _Hidden extends SingleChildRenderObjectWidget {
  const _Hidden({required this.hidden, super.child});

  final bool hidden;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderHidden(hidden);

  @override
  void updateRenderObject(BuildContext context, _RenderHidden renderObject) {
    renderObject.hidden = hidden;
  }
}

class _RenderHidden extends RenderProxyBox {
  _RenderHidden(this._hidden);

  bool _hidden;
  set hidden(bool value) {
    if (value != _hidden) {
      _hidden = value;
      markNeedsPaint();
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (!_hidden) {
      super.paint(context, offset);
    }
  }
}
