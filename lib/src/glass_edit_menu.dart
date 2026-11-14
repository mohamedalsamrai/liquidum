part of 'glass.dart';

/// UIKit's edit menu (`UIEditMenuInteraction`) on iOS 26: the row of
/// actions over a text selection (Cut, Copy, Paste...), on a capsule of
/// glass.
///
/// Give it to a text field as its context menu:
///
/// ```dart
/// CupertinoTextField(contextMenuBuilder: GlassEditMenu.builder)
/// ```
///
/// or show your own items at a point with Flutter's [ContextMenuController]:
///
/// ```dart
/// controller.show(
///   context: context,
///   contextMenuBuilder: (context) => GlassEditMenu(
///     anchors: TextSelectionToolbarAnchors(primaryAnchor: position),
///     items: [
///       GlassMenuItem(label: 'Copy', onPressed: copy),
///       GlassMenuItem(label: 'Reply', onPressed: reply),
///     ],
///   ),
/// );
/// ```
///
/// As UIKit's, the menu sits 15pt below the selection (or the point), and
/// above it when there is no room below; it grows out of the selection's
/// middle and shrinks back into it when it goes. Its glass swells under a
/// finger, as interactive glass does. Items that do not fit across the
/// screen (less 20pt a side) give way to a chevron, which melts the
/// capsule into a full menu of every item; choosing an item, or tapping
/// outside, closes it.
///
/// Choosing one of [items] calls its [GlassMenuItem.onPressed] and closes
/// the menu ([ContextMenuController.removeAny]); Flutter's text actions
/// ([GlassEditMenu.buttonItems]) close or renew it themselves, as with
/// Flutter's own toolbars.
class GlassEditMenu extends StatefulWidget {
  /// A menu of [items] at [anchors]: below
  /// [TextSelectionToolbarAnchors.secondaryAnchor] (or the primary anchor
  /// when there is none), or above the primary anchor.
  const GlassEditMenu({
    super.key,
    required this.anchors,
    required List<GlassMenuItem> this.items,
  }) : buttonItems = null;

  /// A menu of Flutter's text editing actions ([ContextMenuButtonItem]s,
  /// such as [EditableTextState.contextMenuButtonItems] or
  /// [SelectableRegionState.contextMenuButtonItems]), labeled as Cupertino
  /// labels them, with UIKit's symbols; in the full menu, Cut, Copy and
  /// Paste lead as tiles.
  const GlassEditMenu.buttonItems({
    super.key,
    required this.anchors,
    required List<ContextMenuButtonItem> this.buttonItems,
  }) : items = null;

  /// A text field's context menu builder (`contextMenuBuilder:`): its
  /// actions at its selection.
  static Widget builder(
    BuildContext context,
    EditableTextState editableTextState,
  ) => GlassEditMenu.buttonItems(
    anchors: editableTextState.contextMenuAnchors,
    buttonItems: editableTextState.contextMenuButtonItems,
  );

  /// Where the menu goes, in global coordinates.
  final TextSelectionToolbarAnchors anchors;

  final List<GlassMenuItem>? items;
  final List<ContextMenuButtonItem>? buttonItems;

  @override
  State<GlassEditMenu> createState() => _GlassEditMenuState();
}

/// UIKit's edit menu (iOS 26.5): a 46pt capsule of small regular glass, 4pt
/// in; each action 16pt either side of its label (SF 15); a 1 x 20 line
/// between actions; a 36pt circle with a chevron 4pt from the end when
/// actions are left out. 15pt from the selection, 20pt from the screen's
/// sides.
abstract final class _EditMetrics {
  static const double height = 46;
  static const double inset = 4;
  static const double pad = 16;
  static const double separator = 20;
  static const double more = 36;
  static const double gap = 15;
  static const double edge = 20;
  static const double highlight = 38;

  // Showing: scale 0.2 to 1 about the selection's middle and opacity 0 to
  // 1 on one spring, omega 22.8 (hiding 19.1), damping ratio 0.85.
  static const double start = 0.2;
  static const double showResponse = 2 * math.pi / 22.8;
  static const double hideResponse = 2 * math.pi / 19.1;
  static const double damping = 0.85;

  static const TextStyle label = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.23,
  );

  // UIKit's fills: the held action's (tertiary) and the chevron's
  // (quaternary); the lines between actions.
  static Color highlightFill(bool dark) =>
      dark ? const Color(0x3D767680) : const Color(0x1F767680);
  static Color moreFill(bool dark) =>
      dark ? const Color(0x2E767680) : const Color(0x14747480);
  static Color line(bool dark) =>
      dark ? const Color(0x80545458) : const Color(0x1F3C3C43);
}

/// Where the capsule goes and what it shows.
@immutable
class _EditLayout {
  const _EditLayout({
    required this.rect,
    required this.origin,
    required this.anchor,
    required this.items,
    required this.cells,
    required this.more,
    required this.dark,
  });

  /// The glass, settled (global coordinates).
  final Rect rect;

  /// What it grows out of: the selection's middle on the capsule's edge
  /// facing it.
  final Offset origin;

  /// The selection's middle on its side facing the menu (where the full
  /// menu shrinks away to).
  final Offset anchor;

  /// The actions shown, and their cells' widths.
  final List<GlassMenuItem> items;
  final List<double> cells;

  /// Whether actions were left out for the chevron.
  final bool more;
  final bool dark;

  double cellLeft(int i) {
    var x = _EditMetrics.inset;
    for (var k = 0; k < i; k++) {
      x += cells[k];
    }
    return x;
  }
}

class _GlassEditMenuState extends State<GlassEditMenu>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  final GlassSpring _shown = GlassSpring(
    response: _EditMetrics.showResponse,
    dampingRatio: _EditMetrics.damping,
    tolerance: 5e-4,
  );
  final _EditAmount _amount = _EditAmount();
  Duration? _last;
  int? _held;
  bool _expanded = false;
  bool _gone = false;
  GlobalKey<_GlassMenuOverlayState>? _menu;
  _EditLayout? _layout;

  // A copy of the menu above everything, hidden, that plays the hiding once
  // Flutter takes the menu away (it is removed at once, with no chance to
  // animate).
  OverlayEntry? _ghostEntry;
  final GlobalKey<_EditGhostState> _ghost = GlobalKey<_EditGhostState>();
  bool _mirrorQueued = false;
  bool _handedOff = false;

  @override
  void initState() {
    super.initState();
    _shown.target = 1;
    _ticker.start();
    WidgetsBinding.instance.addPostFrameCallback((_) => _addGhost());
  }

  void _addGhost() {
    if (!mounted || _ghostEntry != null) {
      return;
    }
    final OverlayState? overlay = Overlay.maybeOf(context);
    if (overlay == null) {
      return;
    }
    _ghostEntry = OverlayEntry(
      builder: (BuildContext context) => _EditGhost(key: _ghost),
    );
    overlay.insert(_ghostEntry!);
    _queueMirror();
  }

  // After this frame, the copy takes the menu as drawn.
  void _queueMirror() {
    if (_mirrorQueued || _ghostEntry == null) {
      return;
    }
    _mirrorQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mirrorQueued = false;
      final _EditLayout? layout = _layout;
      if (mounted && layout != null) {
        _ghost.currentState?.mirror(layout, _shown.value);
      }
    });
  }

  void _tick(Duration elapsed) {
    final double dt = _last == null
        ? 1 / 60
        : (elapsed - _last!).inMicroseconds / 1e6;
    _last = elapsed;
    _shown.step(dt);
    if (_shown.isSettled) {
      _shown.snap(_shown.target);
      _ticker.stop();
      _last = null;
    }
    _amount.value = _shown.value.clamp(0.0, 1.0);
    setState(() {});
  }

  // Taken out of the tree (during the build, before this frame is drawn;
  // dispose comes after it): the copy shows in the menu's place at once and
  // hides.
  @override
  void deactivate() {
    final OverlayEntry? entry = _ghostEntry;
    final _EditGhostState? ghost = _ghost.currentState;
    if (!_handedOff &&
        entry != null &&
        ghost != null &&
        !_expanded &&
        _shown.value > 0.01) {
      _handedOff = true;
      ghost.play(_shown.value, _shown.velocity, () {
        entry.remove();
        entry.dispose();
      });
    }
    super.deactivate();
  }

  // Put back (moved within the tree): the menu shows again, not its copy.
  @override
  void activate() {
    super.activate();
    if (_handedOff) {
      _handedOff = false;
      _ghost.currentState?.cancel();
    }
  }

  @override
  void dispose() {
    _gone = true;
    _ticker.dispose();
    final OverlayEntry? entry = _ghostEntry;
    _ghostEntry = null;
    if (entry != null && !_handedOff) {
      entry.remove();
      entry.dispose();
    }
    // A full menu still open closes into the selection.
    _menu?.currentState?.close();
    _amount.dispose();
    super.dispose();
  }

  // Flutter's actions as glass menu items, and how many lead as tiles: Cut,
  // Copy and Paste first, then UIKit's groups (Select All; Look Up and
  // Search Web; Share; Scan Text; the rest).
  (List<GlassMenuItem>, int) _items(BuildContext context) {
    final List<ContextMenuButtonItem>? buttons = widget.buttonItems;
    if (buttons == null) {
      return (widget.items!, 0);
    }
    final List<GlassMenuItem> tiles = <GlassMenuItem>[];
    final List<GlassMenuItem> rest = <GlassMenuItem>[];
    int? group;
    for (final ContextMenuButtonItem b in buttons) {
      final GlassMenuItem item = GlassMenuItem(
        label: b.label ?? _label(context, b),
        icon: _icon(b.type),
        onPressed: b.onPressed,
      );
      final int g = switch (b.type) {
        ContextMenuButtonType.cut ||
        ContextMenuButtonType.copy ||
        ContextMenuButtonType.paste => 0,
        ContextMenuButtonType.selectAll => 1,
        ContextMenuButtonType.lookUp || ContextMenuButtonType.searchWeb => 2,
        ContextMenuButtonType.share => 3,
        ContextMenuButtonType.liveTextInput => 4,
        ContextMenuButtonType.delete => 5,
        ContextMenuButtonType.custom => 6,
      };
      if (g == 0 && rest.isEmpty) {
        tiles.add(item);
        continue;
      }
      if (rest.isNotEmpty && g != group) {
        rest.add(const GlassMenuItem.divider());
      }
      group = g;
      rest.add(item);
    }
    return (<GlassMenuItem>[...tiles, ...rest], tiles.length);
  }

  static String _label(BuildContext context, ContextMenuButtonItem item) {
    final CupertinoLocalizations? l = Localizations.of<CupertinoLocalizations>(
      context,
      CupertinoLocalizations,
    );
    if (l == null) {
      return '';
    }
    return CupertinoTextSelectionToolbarButton.getButtonLabel(context, item);
  }

  static IconData? _icon(ContextMenuButtonType type) => switch (type) {
    ContextMenuButtonType.cut => CupertinoIcons.scissors,
    ContextMenuButtonType.copy => CupertinoIcons.doc_on_doc,
    ContextMenuButtonType.paste => CupertinoIcons.doc_on_clipboard,
    ContextMenuButtonType.selectAll => CupertinoIcons.selection_pin_in_out,
    ContextMenuButtonType.lookUp => CupertinoIcons.book,
    ContextMenuButtonType.searchWeb => CupertinoIcons.search,
    ContextMenuButtonType.share => CupertinoIcons.share,
    ContextMenuButtonType.liveTextInput => CupertinoIcons.viewfinder,
    ContextMenuButtonType.delete => CupertinoIcons.trash,
    ContextMenuButtonType.custom => null,
  };

  _EditLayout _place(MediaQueryData media, List<GlassMenuItem> items) {
    final Size screen = media.size;
    final List<double> all = <double>[
      for (final GlassMenuItem item in items) _cellWidth(item, media),
    ];
    final double room = screen.width - 2 * _EditMetrics.edge;
    double sum = all.fold(0, (double a, double b) => a + b);
    var n = items.length;
    final bool more = 2 * _EditMetrics.inset + sum > room;
    if (more) {
      sum = 0;
      n = 0;
      while (n < all.length &&
          2 * _EditMetrics.inset + sum + all[n] + _EditMetrics.more <= room) {
        sum += all[n];
        n++;
      }
      if (n == 0) {
        sum = all.first;
        n = 1;
      }
    }
    final double width =
        2 * _EditMetrics.inset + sum + (more ? _EditMetrics.more : 0);
    // UIKit centers its list (the glass less 8pt, or 6 with the chevron)
    // on the selection's middle.
    final Offset top = widget.anchors.primaryAnchor;
    final Offset bottom = widget.anchors.secondaryAnchor ?? top;
    final double list = width - (more ? 6 : 8);
    final double left = (bottom.dx - list / 2).clamp(
      _EditMetrics.edge,
      math.max(_EditMetrics.edge, screen.width - _EditMetrics.edge - width),
    );
    final double floor =
        screen.height - math.max(media.padding.bottom, media.viewInsets.bottom);
    double y = bottom.dy + _EditMetrics.gap;
    bool above = false;
    if (y + _EditMetrics.height > floor) {
      y = top.dy - _EditMetrics.gap - _EditMetrics.height;
      above = true;
    }
    y = math.max(y, media.padding.top);
    final Rect rect = Rect.fromLTWH(left, y, width, _EditMetrics.height);
    return _EditLayout(
      rect: rect,
      origin: Offset(bottom.dx, above ? rect.bottom : rect.top),
      anchor: above ? top : bottom,
      items: items.sublist(0, n),
      cells: all.sublist(0, n),
      more: more,
      dark: media.platformBrightness == Brightness.dark,
    );
  }

  static double _cellWidth(GlassMenuItem item, MediaQueryData media) {
    final TextPainter text = TextPainter(
      text: TextSpan(text: item.label ?? '', style: _EditMetrics.label),
      textDirection: TextDirection.ltr,
      textScaler: media.textScaler,
      maxLines: 1,
    )..layout();
    // Labels take whole pixels, as UIKit's.
    final double px = 1 / media.devicePixelRatio;
    final double w = (text.width / px).ceilToDouble() * px;
    text.dispose();
    return 2 * _EditMetrics.pad + w;
  }

  void _choose(GlassMenuItem item) {
    if (item.items != null) {
      _expand();
      return;
    }
    setState(() => _held = null);
    item.onPressed?.call();
    // Flutter's text actions take the menu away (or show it anew) of their
    // own; given items close it.
    if (mounted && widget.buttonItems == null) {
      ContextMenuController.removeAny();
    }
  }

  // The chevron: the capsule melts into the full menu of every action.
  void _expand() {
    final _EditLayout? layout = _layout;
    if (layout == null || _expanded) {
      return;
    }
    final (List<GlassMenuItem> items, int tiles) = _items(context);
    setState(() {
      _expanded = true;
      _held = null;
      _menu = _showGlassMenu(
        context: context,
        items: items,
        tiles: tiles,
        source: layout.rect,
        fromEnd: true,
        closeTo: layout.anchor,
        sourceContent: _EditContent(layout: layout, shown: 1, plain: true),
        onClosed: () {
          if (mounted && !_gone) {
            ContextMenuController.removeAny();
          }
        },
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final MediaQueryData media = MediaQuery.of(context);
    final (List<GlassMenuItem> all, _) = _items(context);
    final List<GlassMenuItem> items = <GlassMenuItem>[
      for (final GlassMenuItem item in all)
        if (!item.isDivider) item,
    ];
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }
    final _EditLayout layout = _place(media, items);
    _layout = layout;
    _queueMirror();
    if (_expanded) {
      return const SizedBox.shrink();
    }
    return Stack(
      children: <Widget>[
        _EditCapsule(
          layout: layout,
          shown: _shown.value,
          amount: _amount,
          held: _held,
          onHold: (int? i) => setState(() => _held = i),
          onChoose: (int i) => _choose(layout.items[i]),
          onMore: _expand,
        ),
      ],
    );
  }
}

/// The capsule at [shown] (0 to 1): scaled from 0.2 about its origin, its
/// glass materialized and its labels shown that much.
class _EditCapsule extends StatelessWidget {
  const _EditCapsule({
    required this.layout,
    required this.shown,
    required this.amount,
    this.held,
    this.onHold,
    this.onChoose,
    this.onMore,
  });

  final _EditLayout layout;
  final double shown;
  final Animation<double> amount;
  final int? held;
  final ValueChanged<int?>? onHold;
  final ValueChanged<int>? onChoose;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final double k =
        _EditMetrics.start + (1 - _EditMetrics.start) * math.max(shown, 0);
    final Rect r = layout.rect;
    final Offset o = layout.origin;
    final Rect scaled = Rect.fromLTRB(
      o.dx + (r.left - o.dx) * k,
      o.dy + (r.top - o.dy) * k,
      o.dx + (r.right - o.dx) * k,
      o.dy + (r.bottom - o.dy) * k,
    );
    final bool live = onChoose != null;
    return Positioned.fromRect(
      rect: scaled,
      child: IgnorePointer(
        ignoring: !live || shown < 0.5,
        child: GlassPresence(
          amount: amount,
          // UIKit's edit menu keeps the system's appearance (large glass's
          // fixed face) whatever is behind it.
          child: Glass._fixedFace(
            radius: _EditMetrics.height / 2 * k,
            interactive: live,
            child: OverflowBox(
              alignment: Alignment.topLeft,
              maxWidth: double.infinity,
              maxHeight: double.infinity,
              child: Transform.scale(
                scale: k,
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: r.width,
                  height: r.height,
                  child: _EditContent(
                    layout: layout,
                    shown: shown.clamp(0.0, 1.0),
                    held: held,
                    onHold: onHold,
                    onChoose: onChoose,
                    onMore: onMore,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The capsule's actions, lines and chevron. [plain] labels (not vibrant)
/// for the full menu's morph, which fades them.
class _EditContent extends StatelessWidget {
  const _EditContent({
    required this.layout,
    required this.shown,
    this.held,
    this.onHold,
    this.onChoose,
    this.onMore,
    this.plain = false,
  });

  final _EditLayout layout;
  final double shown;
  final int? held;
  final ValueChanged<int?>? onHold;
  final ValueChanged<int>? onChoose;
  final VoidCallback? onMore;
  final bool plain;

  @override
  Widget build(BuildContext context) {
    final bool dark = layout.dark;
    final List<Widget> marks = <Widget>[];
    final List<Widget> cells = <Widget>[];
    for (var i = 0; i < layout.items.length; i++) {
      final GlassMenuItem item = layout.items[i];
      final double left = layout.cellLeft(i);
      final double width = layout.cells[i];
      final bool enabled = item.onPressed != null || item.items != null;
      // The line before this action, hidden beside the held one.
      if (i > 0 && held != i && held != i - 1) {
        marks.add(
          Positioned(
            left: left,
            top: (_EditMetrics.height - _EditMetrics.separator) / 2,
            width: 1,
            height: _EditMetrics.separator,
            child: ColoredBox(color: _EditMetrics.line(dark)),
          ),
        );
      }
      if (held == i) {
        marks.add(
          Positioned(
            left: left,
            top: (_EditMetrics.height - _EditMetrics.highlight) / 2,
            width: width,
            height: _EditMetrics.highlight,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: _EditMetrics.highlightFill(dark),
                borderRadius: BorderRadius.circular(_EditMetrics.highlight / 2),
              ),
            ),
          ),
        );
      }
      final Color red = GlassTabBarStyle.resolve(
        GlassTabBarStyle.systemRed,
        dark: dark,
      );
      final Widget label = plain || item.destructive
          ? Text(
              item.label ?? '',
              maxLines: 1,
              softWrap: false,
              style: _EditMetrics.label.copyWith(
                color: item.destructive
                    ? red
                    : (dark ? const Color(0xFFFFFFFF) : const Color(0xFF000000))
                          .withValues(alpha: enabled ? 1 : 0.3),
                decoration: TextDecoration.none,
              ),
            )
          : GlassVibrantLabel(
              label: item.label,
              style: _EditMetrics.label,
              enabled: enabled,
              strength: shown,
              pressFade: 0,
            );
      cells.add(
        Positioned(
          left: left,
          top: 0,
          width: width,
          height: _EditMetrics.height,
          child: Semantics(
            button: true,
            enabled: enabled,
            label: item.label,
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: enabled ? (_) => onHold?.call(i) : null,
              onTapCancel: () => onHold?.call(null),
              onTap: enabled ? () => onChoose?.call(i) : null,
              child: Center(
                child: item.destructive && !plain
                    ? Opacity(opacity: shown, child: label)
                    : label,
              ),
            ),
          ),
        ),
      );
    }
    final Color ink = dark ? const Color(0xFFFFFFFF) : const Color(0xFF000000);
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        Positioned.fill(
          child: Opacity(
            opacity: plain ? 1 : shown,
            child: Stack(children: marks),
          ),
        ),
        ...cells,
        if (layout.more)
          Positioned(
            right: _EditMetrics.inset,
            top: (_EditMetrics.height - _EditMetrics.more) / 2,
            width: _EditMetrics.more,
            height: _EditMetrics.more,
            child: Semantics(
              button: true,
              label: 'More',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onMore,
                child: Opacity(
                  opacity: plain ? 1 : shown,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: _EditMetrics.moreFill(dark),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: CustomPaint(
                        size: const Size(11.67, 16),
                        painter: _MenuGlyphPainter(_MenuGlyph.chevron, ink),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// The menu's copy above everything: hidden while the menu shows; once the
/// menu is taken away it shows in its place and shrinks away on UIKit's
/// hiding spring.
class _EditGhost extends StatefulWidget {
  const _EditGhost({super.key});

  @override
  State<_EditGhost> createState() => _EditGhostState();
}

class _EditGhostState extends State<_EditGhost>
    with SingleTickerProviderStateMixin {
  // Made up front: the copy starts it while the tree is locked.
  late final Ticker _ticker;
  final GlassSpring _shown = GlassSpring(
    response: _EditMetrics.hideResponse,
    dampingRatio: _EditMetrics.damping,
    tolerance: 5e-4,
  );
  final _EditAmount _amount = _EditAmount();
  _RenderHidden? _cover;
  _EditLayout? _layout;
  bool _playing = false;
  VoidCallback? _done;
  Duration? _last;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick);
  }

  /// The menu as it is drawn now (after a frame, outside the build).
  void mirror(_EditLayout layout, double shown) {
    if (_playing) {
      return;
    }
    _shown.snap(shown);
    _amount.value = shown.clamp(0.0, 1.0);
    setState(() => _layout = layout);
  }

  /// The menu was taken away (during the build: no rebuild here): show the
  /// copy and hide it from [shown], moving at [velocity].
  void play(double shown, double velocity, VoidCallback done) {
    if (_layout == null) {
      done();
      return;
    }
    _playing = true;
    _done = done;
    _shown
      ..value = shown
      ..velocity = velocity
      ..target = 0;
    _cover?.hidden = false;
    _ticker.start();
  }

  /// The menu came back: hide the copy again.
  void cancel() {
    _playing = false;
    _done = null;
    _cover?.hidden = true;
    _ticker.stop();
    _last = null;
  }

  void _tick(Duration elapsed) {
    final double dt = _last == null
        ? 1 / 60
        : (elapsed - _last!).inMicroseconds / 1e6;
    _last = elapsed;
    _shown.step(dt);
    _amount.value = _shown.value.clamp(0.0, 1.0);
    if (_shown.isSettled || _shown.value <= 0) {
      _ticker.stop();
      final VoidCallback? done = _done;
      _done = null;
      done?.call();
      return;
    }
    setState(() {});
  }

  @override
  void dispose() {
    _cover = null;
    _ticker.dispose();
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final _EditLayout? layout = _layout;
    return IgnorePointer(
      child: ExcludeSemantics(
        child: _GhostCover(
          hidden: !_playing,
          onCreate: (_RenderHidden cover) => _cover = cover,
          child: layout == null
              ? const SizedBox.shrink()
              : Stack(
                  children: <Widget>[
                    _EditCapsule(
                      layout: layout,
                      shown: _shown.value,
                      amount: _amount,
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// The copy's cover: hidden until the copy plays, then shown without a
/// rebuild (the tree is locked when the menu is taken away).
class _GhostCover extends SingleChildRenderObjectWidget {
  const _GhostCover({
    required this.hidden,
    required this.onCreate,
    super.child,
  });

  final bool hidden;
  final ValueChanged<_RenderHidden> onCreate;

  @override
  RenderObject createRenderObject(BuildContext context) {
    final _RenderHidden cover = _RenderHidden(hidden);
    onCreate(cover);
    return cover;
  }

  @override
  void updateRenderObject(BuildContext context, _RenderHidden renderObject) {
    renderObject.hidden = hidden;
  }
}

/// How materialized the menu's glass is, set each frame.
class _EditAmount extends Animation<double>
    with AnimationLocalListenersMixin, AnimationLocalStatusListenersMixin {
  double _value = 0;

  @override
  double get value => _value;
  set value(double v) {
    if (v != _value) {
      _value = v;
      notifyListeners();
    }
  }

  @override
  AnimationStatus get status => AnimationStatus.forward;

  @override
  void didRegisterListener() {}

  @override
  void didUnregisterListener() {}

  void dispose() => clearListeners();
}
