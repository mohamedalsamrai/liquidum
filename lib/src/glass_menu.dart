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

  // Without the checkmark column (no item checked): an icon's center and
  // the label's start after icons.
  static const double plainIconCenter = 40;
  static const double plainLabelWithIcons = 64;

  // The edit menu's leading actions (Cut, Copy, Paste) as tiles across the
  // top: 77pt tall, sharing the width less 8pt a side; the icon centered
  // 29pt down, the label (SF Medium 12, two lines) from 43.67pt; a hairline
  // at their bottom and the first row 11pt below it.
  static const double tile = 77;
  static const double tileSide = 8;
  static const double tileGap = 11;
  static const double tileIcon = 29;
  static const double tileLabel = 43.67;

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

  static double height(List<List<GlassMenuItem>> groups, {bool tiles = false}) {
    final int rows = groups.fold(
      0,
      (int n, List<GlassMenuItem> g) => n + g.length,
    );
    if (tiles && rows == 0) {
      return tile;
    }
    return (tiles ? tile + tileGap : pad) +
        pad +
        rows * row +
        (groups.length - 1) * groupGap;
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

/// UIKit's context menu (`UIContextMenuInteraction`) on iOS 26.5, measured
/// frame by frame: the touched view grows while the finger rests on it,
/// lifts over a dimmed screen once it is a long press, and the menu grows
/// out of its center with the liquid morph, 20pt beside it.
abstract final class _ContextMetrics {
  /// The menu opens this long after the finger went down; the view starts
  /// growing a fifth of a second in.
  static const Duration openDelay = Duration(milliseconds: 800);
  static const Duration pressDelay = Duration(milliseconds: 200);

  // While pressed, the view's longer side grows toward 15.7pt more on a
  // critically damped spring (omega 5.77), whatever its size.
  static const double pressGrowth = 15.7;
  static const double pressResponse = 2 * math.pi / 5.77;

  /// Lifted, it is 1.15 times its size, or 26pt longer on its longer side
  /// when that is less, and kept 20pt from the screen's sides.
  static const double liftScale = 1.15;
  static const double liftGrowth = 26;
  static const double edge = 20;

  /// The menu sits this far from the lifted view, on the side with more
  /// room.
  static const double gap = 20;

  /// The view's corners (continuous, at its own size, so they grow as it
  /// lifts) and its shadow: black at 0.27,
  /// blurred by a sigma of 18.5pt, from the view's opaque pixels.
  static const double radius = 13;
  static const double shadowOpacity = 0.27;
  static const double shadowSigma = 18.5;

  /// The dim over the screen: this color at 0.21, light or dark.
  static const Color dim = Color.fromRGBO(22, 21, 42, 0.21);

  /// The menu starts as 0.4 of the view (each side at most the menu's
  /// shorter side), at the view's center.
  static const double start = 0.4;

  /// The menu's size runs ahead of the progress by this times p(1 - p).
  static const double sizeLead = 0.32;

  // One spring lifts the view and grows the menu: omega 21, damping ratio
  // 0.8 opening; 20.8 and 0.8 closing. The dim: 20.7 and 0.81 in, 16.1
  // and 0.82 out.
  static const double openResponse = 2 * math.pi / 21;
  static const double closeResponse = 2 * math.pi / 20.8;
  static const double damping = 0.8;
  static const double dimInResponse = 2 * math.pi / 20.7;
  static const double dimOutResponse = 2 * math.pi / 16.1;
  static const double dimDamping = 0.81;
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
  Widget? preview,
  bool pressing = false,
  Rect? source,
  bool fromEnd = false,
  Offset? closeTo,
  int tiles = 0,
}) {
  final OverlayState overlay = Overlay.of(context, rootOverlay: true);
  final RenderBox overlayBox = overlay.context.findRenderObject()! as RenderBox;
  // The source's box in the overlay: [context]'s, or [source] (global).
  final Rect local;
  if (source != null) {
    local = Rect.fromPoints(
      overlayBox.globalToLocal(source.topLeft),
      overlayBox.globalToLocal(source.bottomRight),
    );
  } else {
    final RenderBox box = context.findRenderObject()! as RenderBox;
    local = MatrixUtils.transformRect(
      box.getTransformTo(overlayBox),
      Offset.zero & box.size,
    );
  }
  final Offset? closeLocal = closeTo == null
      ? null
      : overlayBox.globalToLocal(closeTo);
  final GlobalKey<_GlassMenuOverlayState> key =
      GlobalKey<_GlassMenuOverlayState>();
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (BuildContext context) => _GlassMenuOverlay(
      key: key,
      source: local,
      items: items,
      sourceContent: sourceContent,
      fromEnd: fromEnd,
      closeTo: closeLocal,
      tiles: tiles,
      preview: preview == null
          ? null
          : InheritedTheme.captureAll(context, preview, to: overlay.context),
      pressing: pressing,
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
    this.preview,
    this.pressing = false,
    this.fromEnd = false,
    this.closeTo,
    this.tiles = 0,
  });

  final Rect source;

  /// The source melts from its end (its trailing circle): an edit menu's
  /// capsule into its chevron, the menu growing out of there.
  final bool fromEnd;

  /// Where the menu shrinks away to when it closes (the source is gone by
  /// then: an edit menu's, which does not come back); null for the source.
  final Offset? closeTo;

  /// How many of [items] lead as tiles across the top (an edit menu's Cut,
  /// Copy and Paste).
  final int tiles;
  final List<GlassMenuItem> items;
  final Widget sourceContent;
  final VoidCallback onClosed;

  /// A context menu's view, drawn lifted over the dimmed screen (the menu
  /// grows out of its center and no source glass is drawn); null for a
  /// menu that grows out of glass.
  final Widget? preview;

  /// A context menu whose finger is still resting: the view grows until
  /// [_GlassMenuOverlayState.open] (or shrinks back on
  /// [_GlassMenuOverlayState.cancelPress]).
  final bool pressing;

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

  // A context menu: how much the resting finger has grown the view (on its
  // longer side), the dim, the lifted view's box, and where the lift
  // starts from (the pressed view opening, the source closing).
  bool get _isContext => widget.preview != null;
  late bool _pressing = widget.pressing;
  final GlassSpring _press = GlassSpring(
    response: _ContextMetrics.pressResponse,
    dampingRatio: 1,
    tolerance: 0.01,
  );
  final GlassSpring _dim = GlassSpring(
    response: _ContextMetrics.dimInResponse,
    dampingRatio: _ContextMetrics.dimDamping,
  );
  Rect? _lift;
  Rect _from = Rect.zero;
  List<List<GlassMenuItem>> _groups = const <List<GlassMenuItem>>[];
  List<GlassMenuItem> _tiles = const <GlassMenuItem>[];

  // The source the menu grows out of and goes back into: a point once an
  // edit menu's capsule is gone ([_GlassMenuOverlay.closeTo]).
  late Rect _src = widget.source;
  bool _sourceGone = false;

  // Where the source melts to and the menu grows from: the source, or the
  // circle at its end.
  Rect get _origin => widget.fromEnd && !_sourceGone
      ? Rect.fromLTWH(
          _src.right - _src.height,
          _src.top,
          _src.height,
          _src.height,
        )
      : _src;
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
    var y =
        menu.top +
        (_tiles.isEmpty
            ? _MenuMetrics.pad
            : _MenuMetrics.tile + _MenuMetrics.tileGap);
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
    // A context menu's finger starts on the view: the menu's glass answers
    // it once it comes over the menu.
    final bool near =
        !_isContext || (_menu != null && _menu!.inflate(16).contains(position));
    if (box is RenderBox && position.isFinite && near) {
      _feed.move(box.localToGlobal(position));
    } else {
      _feed.up();
    }
  }

  /// A context menu's view: the box it covers while the finger rests (its
  /// longer side grown by [_press]'s points, up to its lifted size).
  Rect _pressed() {
    final Rect s = widget.source;
    final double longer = math.max(s.longestSide, 1);
    final double k = math.min(
      1 + math.max(_press.value, 0) / longer,
      _liftScale(MediaQuery.sizeOf(context)),
    );
    return Rect.fromCenter(
      center: s.center,
      width: s.width * k,
      height: s.height * k,
    );
  }

  // 1.15, or 26pt more on the longer side when that is less; no more than
  // fits between the screen's sides less 20pt each.
  double _liftScale(Size screen) {
    final Rect s = widget.source;
    final double longer = math.max(s.longestSide, 1);
    double k = math.min(
      _ContextMetrics.liftScale,
      (longer + _ContextMetrics.liftGrowth) / longer,
    );
    final double room = screen.width - 2 * _ContextMetrics.edge;
    if (s.width * k > room) {
      k = math.max(1, room / math.max(s.width, 1));
    }
    return k;
  }

  /// The finger has rested long enough: the view lifts, the screen dims and
  /// the menu grows out of the view.
  void open() {
    if (!_isContext || !_pressing || _closing) {
      return;
    }
    _from = _pressed();
    _pressing = false;
    _progress
      ..configure(_ContextMetrics.openResponse, _ContextMetrics.damping)
      ..target = 1;
    _dim.target = 1;
    setState(() {});
    _wake();
  }

  /// The finger lifted or moved away before the menu opened: the view
  /// shrinks back and the overlay goes.
  void cancelPress() {
    if (!_pressing || _closing) {
      return;
    }
    _closing = true;
    _press
      ..configure(_ContextMetrics.closeResponse, _ContextMetrics.damping)
      ..target = 0;
    _wake();
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
    if (_isContext) {
      if (_pressing) {
        _press.target = _ContextMetrics.pressGrowth;
      } else {
        // Opened at once (by an assistive technology's long press).
        _progress.configure(
          _ContextMetrics.openResponse,
          _ContextMetrics.damping,
        );
        _progress.target = 1;
        _dim.target = 1;
      }
    } else {
      _progress.target = 1;
      _narrow.target = 1;
    }
    _ticker.start();
  }

  // Where the menu goes: from the source's top corner down, or from its
  // bottom corner up when it would not fit below (its rows reversed, as
  // UIKit's); from its left edge, or its right edge near the screen's
  // right.
  Rect _place(Size screen, EdgeInsets safe, double height) {
    final Rect s = _src;
    const double margin = 8;
    double left = s.left;
    if (widget.fromEnd || left + _MenuMetrics.width > screen.width - margin) {
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
    final Rect s = _src;
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
      if (_pressing) {
        cancelPress();
        return;
      }
      widget.onClosed();
      return;
    }
    _closing = true;
    // An open submenu folds back as the menu morphs away.
    _subSpring.target = 0;
    if (_isContext) {
      // The view settles back into its place, the dim fades, the menu
      // shrinks back into the view's center.
      _from = widget.source;
      _progress
        ..configure(_ContextMetrics.closeResponse, _ContextMetrics.damping)
        ..target = 0;
      _dim
        ..configure(_ContextMetrics.dimOutResponse, _ContextMetrics.dimDamping)
        ..target = 0;
      _wake();
      return;
    }
    if (widget.closeTo != null) {
      _src = Rect.fromCenter(center: widget.closeTo!, width: 0, height: 0);
      _sourceGone = true;
    }
    final Rect s = _src;
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
    _press.step(dt);
    _dim.step(dt);
    if (_sub != null && _subSpring.target == 0 && _subSpring.isSettled) {
      _sub = null;
    }
    if (_progress.isSettled &&
        _narrow.isSettled &&
        _y.isSettled &&
        _subSpring.isSettled &&
        _dim.isSettled &&
        _press.isSettled) {
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
    if (_isContext) {
      return _buildContext(media);
    }
    final int tiles = math.min(widget.tiles, widget.items.length);
    final List<List<GlassMenuItem>> groups = _MenuMetrics.groups(
      widget.items.sublist(tiles),
    );
    final double height = _MenuMetrics.height(groups, tiles: tiles > 0);
    if (_menu == null) {
      _menu = _place(media.size, media.padding, height);
      _start(_menu!);
      _tiles = widget.items.sublist(0, tiles);
      // Rows reversed when the menu goes up (tiles stay on top).
      _groups = _up && tiles == 0
          ? groups.reversed
                .map((List<GlassMenuItem> g) => g.reversed.toList())
                .toList()
          : groups;
    }
    final Rect menu = _menu!;
    final Rect s = _src;
    final Rect o = _origin;
    final double p = _progress.value;
    final bool dark = media.platformBrightness == Brightness.dark;

    // The source: shrinks to a quarter, a quarter of the way to the
    // menu's center, its capsule narrowing to a circle.
    final double ks = 1 + (_MorphSprings.sourceEnd - 1) * p;
    // (Melting from its end, it narrows into its end's circle.)
    final double sw = ui.lerpDouble(s.width, s.height, _narrow.value)!;
    final Offset base = Offset(
      ui.lerpDouble(s.center.dx, o.center.dx, _narrow.value)!,
      s.center.dy,
    );
    final Offset sc =
        base + (menu.center - base) * (_MorphSprings.sourceEnd * p);
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
      center: Offset(ui.lerpDouble(o.center.dx, menu.center.dx, p)!, _y.value),
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
              if ((p < 0.999 || _closing) && !_sourceGone)
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
              _menuGlass(
                menu: menu,
                menuRect: menuRect,
                radius: radius,
                scale: km * recede,
                q: q,
                dark: dark,
                shown: shown,
              ),
            ],
          ),
        ),
        if (_sub != null) _submenu(media, dark, q),
      ],
    );
  }

  // Where a context menu's view lifts to, and where its menu goes: the view
  // grown about its center and kept 20pt from the screen's sides; the menu
  // 20pt from it on the side with more room (the view moving away when the
  // menu would not fit there), from its left edge, or from its right edge
  // near the screen's right. The rows keep their order either way.
  void _placeContext(Size screen, EdgeInsets safe, double height) {
    final Rect s = widget.source;
    final double k = _liftScale(screen);
    final double w = s.width * k;
    final double h = s.height * k;
    const double edge = _ContextMetrics.edge;
    const double gap = _ContextMetrics.gap;
    const double margin = 8;
    final double left = (s.center.dx - w / 2).clamp(
      edge,
      math.max(edge, screen.width - edge - w),
    );
    double top = s.center.dy - h / 2;
    final double minY = safe.top + margin;
    final double maxY = screen.height - safe.bottom - margin;
    _up = top - minY > maxY - (top + h);
    if (_up) {
      top = math.min(math.max(top, minY + height + gap), maxY - h);
    } else {
      top = math.max(math.min(top, maxY - height - gap - h), minY);
    }
    _lift = Rect.fromLTWH(left, top, w, h);
    double menuLeft = left;
    if (menuLeft + _MenuMetrics.width > screen.width - margin) {
      menuLeft = left + w - _MenuMetrics.width;
    }
    menuLeft = menuLeft.clamp(
      margin,
      math.max(margin, screen.width - margin - _MenuMetrics.width),
    );
    _menu = Rect.fromLTWH(
      menuLeft,
      _up ? top - gap - height : top + h + gap,
      _MenuMetrics.width,
      height,
    );
  }

  // A context menu: the dim, the menu growing out of the view's center
  // (from 0.4 of the view, a capsule), and the view, lifted, over both.
  Widget _buildContext(MediaQueryData media) {
    final Rect s = widget.source;
    final bool dark = media.platformBrightness == Brightness.dark;
    if (_menu == null && !_pressing && !_closing) {
      _groups = _MenuMetrics.groups(widget.items);
      _placeContext(media.size, media.padding, _MenuMetrics.height(_groups));
      if (_from == Rect.zero) {
        _from = s;
      }
    }
    final Rect? menu = _menu;
    final double p = _progress.value;
    final double pc = p.clamp(0.0, 1.0);
    final Rect view = menu == null ? _pressed() : Rect.lerp(_from, _lift, p)!;
    final double dim = _dim.value.clamp(0.0, 1.0);
    final double q = _sub == null ? 0 : _subSpring.value;
    final List<Widget> children = <Widget>[
      Positioned.fill(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: close,
          child: dim > 0.001
              ? ColoredBox(
                  color: _ContextMetrics.dim.withValues(
                    alpha: _ContextMetrics.dim.a * dim,
                  ),
                )
              : null,
        ),
      ),
    ];
    if (menu != null) {
      final double side = math.min(_MenuMetrics.width, menu.height);
      final double w0 = math.max(
        _ContextMetrics.start * math.min(s.width, side),
        1,
      );
      final double h0 = math.max(
        _ContextMetrics.start * math.min(s.height, side),
        1,
      );
      // Its center travels with the progress; its size grows by ratios
      // (geometrically), a little ahead of it (fitted to UIKit's frames
      // within 0.7pt rms).
      final double g = p + _ContextMetrics.sizeLead * p * (1 - p);
      final Rect morph = Rect.fromCenter(
        center: Offset.lerp(s.center, menu.center, p)!,
        width: w0 * math.pow(menu.width / w0, g),
        height: h0 * math.pow(menu.height / h0, g),
      );
      final double km = morph.width / _MenuMetrics.width;
      // A capsule at first, round until about halfway, then its corners.
      final double radius = math.min(
        morph.shortestSide / 2,
        km *
            ui.lerpDouble(
              _MenuMetrics.width / 2,
              _MenuMetrics.radius,
              pc * pc,
            )!,
      );
      final double recede = 1 - 0.03 * q;
      children.add(
        GlassGroup(
          brightness: media.platformBrightness,
          child: Stack(
            children: <Widget>[
              _menuGlass(
                menu: menu,
                menuRect: Rect.fromLTWH(
                  morph.left,
                  morph.top,
                  morph.width * recede,
                  morph.height * recede,
                ),
                radius: math.max(radius, 0),
                scale: km * recede,
                q: q,
                dark: dark,
                shown: pc,
              ),
            ],
          ),
        ),
      );
    }
    children.add(
      Positioned.fromRect(
        rect: view,
        child: IgnorePointer(
          child: _ContextPreview(
            size: s.size,
            scale: view.width / math.max(s.width, 1),
            shadow: menu == null ? 0 : pc,
            child: widget.preview!,
          ),
        ),
      ),
    );
    if (_sub != null) {
      children.add(_submenu(media, dark, q));
    }
    // While the finger rests (or the view shrinks back), touches go to the
    // page.
    return IgnorePointer(
      ignoring: menu == null,
      child: Stack(children: children),
    );
  }

  // The menu's glass at [menuRect], its rows laid out at [menu]'s size and
  // scaled by [scale] from the top center, fading in through a blur by
  // [shown]; dimmed under a submenu open by [q].
  Widget _menuGlass({
    required Rect menu,
    required Rect menuRect,
    required double radius,
    required double scale,
    required double q,
    required bool dark,
    required double shown,
  }) {
    final double p = _progress.value;
    return Positioned.fromRect(
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
              scale: scale,
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
                                tiles: _tiles,
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
                            tiles: _tiles,
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
    this.tiles = const <GlassMenuItem>[],
    required this.dark,
    this.hidden,
    required this.highlight,
    required this.onHighlight,
    required this.onChoose,
  });

  final List<List<GlassMenuItem>> groups;

  /// Items shown as tiles across the top (an edit menu's Cut, Copy, Paste).
  final List<GlassMenuItem> tiles;
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
    final bool rows = groups.any((List<GlassMenuItem> g) => g.isNotEmpty);
    final List<Widget> children = <Widget>[
      if (tiles.isEmpty) const SizedBox(height: _MenuMetrics.pad),
      if (tiles.isNotEmpty)
        SizedBox(
          height: _MenuMetrics.tile,
          width: _MenuMetrics.width,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: _MenuMetrics.tileSide,
            ),
            child: Row(
              children: <Widget>[
                for (final GlassMenuItem item in tiles)
                  Expanded(
                    child: _GlassMenuTile(
                      item: item,
                      dark: dark,
                      highlighted: identical(item, highlight),
                      onHighlight: onHighlight,
                      onChoose: onChoose,
                    ),
                  ),
              ],
            ),
          ),
        ),
      if (tiles.isNotEmpty && rows)
        SizedBox(
          height: _MenuMetrics.tileGap,
          child: Align(
            alignment: Alignment.topCenter,
            child: Container(
              height: 1,
              margin: const EdgeInsets.symmetric(
                horizontal: _MenuMetrics.dividerInset,
              ),
              color: divider,
            ),
          ),
        ),
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
    // A checkmark column only when an item is checked.
    final double iconCenter = checks
        ? _MenuMetrics.iconCenter
        : _MenuMetrics.plainIconCenter;
    final double labelStart = icons
        ? (checks
              ? _MenuMetrics.labelWithIcons
              : _MenuMetrics.plainLabelWithIcons)
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
                  left: iconCenter - 12,
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

/// An edit menu's leading action as a tile (UIKit's medium menu element):
/// its icon over its label, centered.
class _GlassMenuTile extends StatelessWidget {
  const _GlassMenuTile({
    required this.item,
    required this.dark,
    required this.highlighted,
    required this.onHighlight,
    required this.onChoose,
  });

  final GlassMenuItem item;
  final bool dark;
  final bool highlighted;
  final ValueChanged<GlassMenuItem?> onHighlight;
  final ValueChanged<GlassMenuItem> onChoose;

  @override
  Widget build(BuildContext context) {
    final bool enabled = item.onPressed != null;
    final Color base = dark ? const Color(0xF5FFFFFF) : const Color(0xF5000000);
    final Color color = !enabled
        ? base.withValues(alpha: 0.3)
        : item.destructive
        ? GlassTabBarStyle.resolve(GlassTabBarStyle.systemRed, dark: dark)
        : base;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => onHighlight(item) : null,
      onTapCancel: () => onHighlight(null),
      onTapUp: enabled ? (_) => onHighlight(null) : null,
      onTap: enabled ? () => onChoose(item) : null,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: item.label,
        child: Stack(
          children: <Widget>[
            if (highlighted)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: dark
                        ? const Color(0x24FFFFFF)
                        : const Color(0x14000000),
                    borderRadius: BorderRadius.circular(_MenuMetrics.row / 2),
                  ),
                ),
              ),
            if (item.icon != null)
              Positioned(
                left: 0,
                right: 0,
                top: _MenuMetrics.tileIcon - 12,
                height: 24,
                child: Center(child: Icon(item.icon, size: 21, color: color)),
              ),
            Positioned(
              left: 2,
              right: 2,
              top: _MenuMetrics.tileLabel,
              child: Text(
                item.label ?? '',
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  height: 16.33 / 12,
                  fontWeight: FontWeight.w500,
                  color: color,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
          ],
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

/// A context menu's view in the overlay: [child] laid out at [size] and
/// drawn [scale] times larger, its corners continuous (13pt at its own
/// size), over a shadow cast by its opaque pixels ([shadow] of UIKit's: black at 0.27, a sigma
/// of 18.5pt).
class _ContextPreview extends StatelessWidget {
  const _ContextPreview({
    required this.size,
    required this.scale,
    required this.shadow,
    required this.child,
  });

  final Size size;
  final double scale;
  final double shadow;
  final Widget child;

  // The corners are the view's own 13pt, growing with it (14.3pt on a
  // label lifted 1.103 times, as UIKit's).
  Widget _view() => OverflowBox(
    alignment: Alignment.topLeft,
    minWidth: size.width,
    maxWidth: size.width,
    minHeight: size.height,
    maxHeight: size.height,
    child: Transform.scale(
      scale: scale,
      alignment: Alignment.topLeft,
      child: ClipRSuperellipse(
        borderRadius: const BorderRadius.all(
          Radius.circular(_ContextMetrics.radius),
        ),
        child: child,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.none,
      children: <Widget>[
        if (shadow > 0.002)
          ImageFiltered(
            imageFilter: ui.ImageFilter.compose(
              outer: ui.ImageFilter.blur(
                sigmaX: _ContextMetrics.shadowSigma,
                sigmaY: _ContextMetrics.shadowSigma,
                tileMode: TileMode.decal,
              ),
              inner: ui.ColorFilter.mode(
                Color.fromRGBO(0, 0, 0, _ContextMetrics.shadowOpacity * shadow),
                BlendMode.srcIn,
              ),
            ),
            child: _view(),
          ),
        _view(),
      ],
    );
  }
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
      hidden: open || _GlassHiddenScope.above(context),
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
