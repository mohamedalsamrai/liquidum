import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../frame_sampler.dart';
import '../glass.dart';
import '../glass_backdrop.dart';
import '../tab_bar/glyphs.dart';
import '../tab_bar/style.dart';
import 'item.dart';
import 'scroll_edge.dart';

/// A page with UIKit's iOS 26 bars: a navigation bar of glass at the top
/// (a [title], a back button, [leading] and [actions] items) and a
/// [toolbar] or a search field at the bottom, over [child], which scrolls
/// under them.
///
/// ```dart
/// GlassPage(
///   title: 'Detail',
///   onBack: () => Navigator.pop(context),
///   actions: [
///     GlassBarItem(icon: CupertinoIcons.ellipsis, onPressed: more),
///     GlassBarItem(icon: CupertinoIcons.add, onPressed: add),
///   ],
///   toolbar: [
///     GlassBarItem(icon: CupertinoIcons.trash, onPressed: delete),
///     GlassBarItem.space(),
///     GlassBarItem(label: 'Done', prominent: true, onPressed: done),
///   ],
///   child: ListView(children: rows),
/// )
/// ```
///
/// As UIKit's (measured on iOS 26.5): the items are interactive glass, 44pt
/// tall at the top and 48pt at the bottom, icons side by side sharing one
/// capsule; the title is centered; a [largeTitle] scrolls away with the
/// content into the bar's title. Where content passes under a bar, UIKit's
/// scroll-edge effect softens it: blurred a little, and dimmed over dark
/// content or washed white over light content, the title turning white or
/// black with it.
///
/// An item with a [GlassBarItem.menu] opens it out of its glass, as
/// UIKit's. Holding the back button opens UIKit's history: the titles of
/// the [GlassPage]s under this one in its [Navigator], nearest first;
/// choosing one goes back to it (lifting the finger on a row chooses it).
///
/// [child] gets the bars' heights as its [MediaQueryData.padding], so a
/// [ListView] or [CustomScrollView] starts below the navigation bar and
/// ends above the toolbar, and scrolls under both. The page reads the
/// scroll position from the first vertical scroll view in [child].
///
/// A search field takes the toolbar's place when any of [searchController],
/// [onSearchChanged] or [onSearchSubmitted] is set (a page has a toolbar or
/// a search field, not both). Tapped, the field makes room for a close
/// button and the navigation bar steps aside, as UIKit's.
class GlassPage extends StatefulWidget {
  const GlassPage({
    super.key,
    this.title,
    this.largeTitle = false,
    this.onBack,
    this.leading = const <GlassBarItem>[],
    this.actions = const <GlassBarItem>[],
    this.toolbar = const <GlassBarItem>[],
    this.searchController,
    this.searchPlaceholder = 'Search',
    this.onSearchChanged,
    this.onSearchSubmitted,
    this.backgroundColor,
    required this.child,
  }) : assert(
         toolbar.length == 0 ||
             (searchController == null &&
                 onSearchChanged == null &&
                 onSearchSubmitted == null),
         'A page has a toolbar or a search field, not both.',
       );

  final String? title;

  /// Shows [title] large under the bar (UIKit's large title), scrolling away
  /// with the content into the bar.
  final bool largeTitle;

  /// Shows UIKit's back button, a glass circle at the leading end, and calls
  /// this when it is tapped.
  final VoidCallback? onBack;

  /// Items at the bar's leading end, after the back button.
  final List<GlassBarItem> leading;

  /// Items at the bar's trailing end.
  final List<GlassBarItem> actions;

  /// Items in the toolbar at the bottom. [GlassBarItem.space] spreads them.
  final List<GlassBarItem> toolbar;

  /// The search field's text.
  final TextEditingController? searchController;

  /// Shown while the search field is empty.
  final String searchPlaceholder;
  final ValueChanged<String>? onSearchChanged;
  final ValueChanged<String>? onSearchSubmitted;

  /// Painted behind [child]. Defaults to the theme's background.
  final Color? backgroundColor;

  final Widget child;

  @override
  State<GlassPage> createState() => _GlassPageState();
}

/// UIKit's bar metrics (iPhone, iOS 26.5).
abstract final class _Bars {
  /// The navigation bar: 54pt under the status bar; its glass 44pt tall at
  /// its top, 20pt from the screen's sides, 12pt apart.
  static const double navHeight = 54;
  static const double platter = 44;
  static const double navSide = 20;
  static const double gap = 12;

  /// Items in a navigation bar platter: 36pt tall, 4pt in, 16pt apart; an
  /// icon is its symbol's box plus 14, a label itself plus 24.
  static const double navItem = 36;
  static const double navInset = 4;
  static const double navItemGap = 16;
  static const double iconBox = 23.33;

  /// Icons are drawn at 26pt: UIKit's bar symbols come out about a fifth
  /// larger than a glass button's (its plus 17.67pt across, trash 21 x 24).
  static const double iconSize = 26;
  static const double navIconSide = 7;
  static const double navTextSide = 12;

  /// The large title's row under the bar, and the title 4pt into it.
  static const double largeRow = 52;
  static const double largeTop = 4;

  /// The toolbar: 48pt tall, 28pt from the screen's sides (and from its
  /// bottom, on iPhones with a home indicator). Items are buttons 38pt
  /// tall, 5pt in, in slots 5pt wider each side and 4pt apart: an icon its
  /// symbol's box plus 16, a label itself plus 22. A lone icon is a 48pt
  /// circle.
  static const double toolHeight = 48;
  static const double toolSide = 28;
  static const double toolInset = 5;
  static const double slotGap = 4;
  static const double toolIconSide = 8;
  static const double toolTextSide = 11;

  /// A pressed item's strength: UIKit's navigation bar items all but vanish
  /// under the finger (0.1), its toolbar items fade to about 0.6; the other
  /// items on the glass keep theirs.
  static const double navHighlight = 0.1;

  /// And the other items on pressed glass fade a little (UIKit's "..."
  /// beside a pressed "+" kept 0.87 of its contrast, under the glow).
  static const double pressFade = 0.15;
  static const double toolHighlight = 0.6;

  /// The search field, focused: room for a 48pt close circle 12pt away.
  static const double closeGap = 12;

  /// The scroll-edge effect: its line at the bottom of the navigation bar's
  /// glass, reaching 64.8pt below it; under the toolbar, its line 10pt
  /// into the toolbar's glass, reaching 74.8pt above it.
  static const double topReach = 64.8;
  static const double bottomLine = 10;
  static const double bottomReach = 74.8;

  static const TextStyle title = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.43,
  );
  static const TextStyle item = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.43,
  );
  static const TextStyle prominentItem = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.43,
  );
  // SF Pro Display, as UIKit's 34pt title (Flutter's default text family
  // draws it in SF Pro Text, larger and wider).
  static const TextStyle large = TextStyle(
    fontFamily: 'CupertinoSystemDisplay',
    fontSize: 34,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.4,
  );
}

class _GlassPageState extends State<GlassPage> with TickerProviderStateMixin {
  // How far the content has scrolled under the navigation bar.
  final ValueNotifier<double> _offset = ValueNotifier<double>(0);

  // The scroll-edge effects: whether the top one shows (content under the
  // bar), and each one's look.
  late final AnimationController _topShown = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 250),
  );
  late final _EdgeLook _topLook = _EdgeLook(this);
  late final _EdgeLook _bottomLook = _EdgeLook(this);
  // With a large title, the top effect's blur: only once the title has
  // collapsed into the bar (UIKit hides its blur until then).
  late final AnimationController _blurOn = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 250),
  );
  late final AnimationController _bottomShown = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 250),
  );

  // The search field: focused (1) or not.
  late final AnimationController _searching = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 350),
  );
  final FocusNode _searchFocus = FocusNode();
  TextEditingController? _ownSearch;

  late final FrameSampler _sampler;
  bool _sampling = false;
  bool _systemDark = false;
  bool _started = false;

  // The effects' areas, in global coordinates, from the last layout.
  Rect? _topArea;
  Rect? _bottomArea;

  bool get _hasSearch =>
      widget.searchController != null ||
      widget.onSearchChanged != null ||
      widget.onSearchSubmitted != null;

  TextEditingController get _search =>
      widget.searchController ?? (_ownSearch ??= TextEditingController());

  @override
  void initState() {
    super.initState();
    _sampler = FrameSampler(
      interval: const Duration(milliseconds: 250),
      sample: _sample,
    );
    _searchFocus.addListener(_focusChanged);
    _blurOn.value = widget.largeTitle ? 0 : 1;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bool dark =
        MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    if (!_started || dark != _systemDark) {
      _systemDark = dark;
      _topLook.reset(dark: dark);
      _bottomLook.reset(dark: dark);
      _started = true;
    }
    final NavigatorState? navigator = Navigator.maybeOf(context);
    if (navigator != _navigator) {
      _leaveStack();
      _navigator = navigator;
      if (navigator != null) {
        (_stacks[navigator] ??= <_GlassPageState>[]).add(this);
      }
    }
  }

  // The pages open in each navigator, bottom first: the back button's
  // history (UIKit's long press on the back button lists the pages under
  // this one, nearest first, and goes back to the one chosen).
  static final Expando<List<_GlassPageState>> _stacks =
      Expando<List<_GlassPageState>>();
  NavigatorState? _navigator;

  void _leaveStack() {
    final NavigatorState? navigator = _navigator;
    if (navigator != null) {
      _stacks[navigator]?.remove(this);
    }
  }

  List<GlassMenuItem> _history() {
    final NavigatorState? navigator = _navigator;
    final ModalRoute<Object?>? own = ModalRoute.of(context);
    final List<_GlassPageState>? stack = navigator == null
        ? null
        : _stacks[navigator];
    if (stack == null || own == null) {
      return const <GlassMenuItem>[];
    }
    final List<GlassMenuItem> items = <GlassMenuItem>[];
    final Set<Route<Object?>> seen = <Route<Object?>>{own};
    for (final _GlassPageState page in stack.reversed) {
      if (!page.mounted) {
        continue;
      }
      final ModalRoute<Object?>? route = ModalRoute.of(page.context);
      final String? title = page.widget.title;
      if (route == null ||
          !route.isActive ||
          seen.contains(route) ||
          title == null) {
        continue;
      }
      // Only the pages under this one.
      if (stack.indexOf(page) > stack.indexOf(this)) {
        continue;
      }
      seen.add(route);
      items.add(
        GlassMenuItem(
          label: title,
          onPressed: () =>
              navigator!.popUntil((Route<Object?> r) => r == route),
        ),
      );
    }
    return items;
  }

  @override
  void dispose() {
    _leaveStack();
    _sampler.dispose();
    _searchFocus
      ..removeListener(_focusChanged)
      ..dispose();
    _ownSearch?.dispose();
    _offset.dispose();
    _topShown.dispose();
    _topLook.dispose();
    _blurOn.dispose();
    _bottomShown.dispose();
    _bottomLook.dispose();
    _searching.dispose();
    super.dispose();
  }

  void _focusChanged() {
    if (_searchFocus.hasFocus) {
      _searching.animateTo(1, curve: Curves.easeOutCubic);
    } else {
      _searching.animateBack(0, curve: Curves.easeOutCubic);
    }
  }

  void _closeSearch() {
    _search.clear();
    widget.onSearchChanged?.call('');
    _searchFocus.unfocus();
  }

  bool _onScroll(ScrollNotification n) {
    if (n.depth == 0) {
      _scrolled(n.metrics);
    }
    return false;
  }

  bool _onMetrics(ScrollMetricsNotification n) {
    if (n.depth == 0) {
      _scrolled(n.metrics);
    }
    return false;
  }

  // UIKit's effects show where a scroll view's content is under a bar: at
  // the top once it has scrolled, at the bottom while there is more below.
  void _scrolled(ScrollMetrics m) {
    if (m.axis != Axis.vertical) {
      return;
    }
    final double offset = m.pixels - m.minScrollExtent;
    _offset.value = offset;
    _show(_topShown, offset > 0.5);
    _show(_blurOn, !widget.largeTitle || offset >= _Bars.largeRow);
    _show(_bottomShown, m.maxScrollExtent - m.pixels > 0.5);
  }

  static void _show(AnimationController c, bool shown) {
    if (shown && c.status != AnimationStatus.forward && c.value < 1) {
      c.forward();
    } else if (!shown && c.status != AnimationStatus.reverse && c.value > 0) {
      c.reverse();
    }
  }

  Future<void> _sample() async {
    if (_sampling || !mounted) {
      return;
    }
    _sampling = true;
    try {
      final Rect? top = _topArea;
      if (top != null && _topShown.value > 0) {
        final double? luma = await glassBackdropUnder(top)?.luminance(top);
        if (mounted && luma != null) {
          _topLook.sample(luma, dark: _systemDark);
        }
      }
      final Rect? bottom = _bottomArea;
      if (bottom != null && mounted && _bottomShown.value > 0) {
        final double? luma = await glassBackdropUnder(
          bottom,
        )?.luminance(bottom);
        if (mounted && luma != null) {
          _bottomLook.sample(luma, dark: _systemDark);
        }
      }
    } finally {
      _sampling = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final MediaQueryData media = MediaQuery.of(context);
    final double top = media.padding.top;
    final bool hasBottom = widget.toolbar.isNotEmpty || _hasSearch;
    final double large = widget.largeTitle ? _Bars.largeRow : 0;
    final Color background =
        widget.backgroundColor ??
        CupertinoTheme.of(context).scaffoldBackgroundColor;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Size size = constraints.biggest;
        // The bottom bar: 28pt from the screen's bottom (6pt into the home
        // indicator's 34pt), above the keyboard when it is up.
        final double keyboard = media.viewInsets.bottom;
        final double bottomMargin = keyboard > 0
            ? keyboard + 8
            : math.max(media.padding.bottom - 6, 8);
        final double barTop = size.height - bottomMargin - _Bars.toolHeight;
        final double contentBottom = hasBottom
            ? size.height - barTop
            : media.padding.bottom;
        final double line = top + _Bars.platter;
        final double bottomLine = barTop + _Bars.bottomLine;

        _recordAreas(size, line, bottomLine, hasBottom);

        final Widget content = MediaQuery(
          data: media.copyWith(
            padding: media.padding.copyWith(
              top: top + _Bars.navHeight + large,
              bottom: contentBottom,
            ),
          ),
          child: NotificationListener<ScrollMetricsNotification>(
            onNotification: _onMetrics,
            child: NotificationListener<ScrollNotification>(
              onNotification: _onScroll,
              child: widget.child,
            ),
          ),
        );

        final Widget page = Stack(
          children: <Widget>[
            // What the glass reads its light or dark look from: the
            // background, the content and the large title.
            Positioned.fill(
              child: GlassBackdrop(
                child: ColoredBox(
                  color: background,
                  child: Stack(
                    children: <Widget>[
                      Positioned.fill(child: content),
                      if (widget.largeTitle && widget.title != null)
                        _largeTitle(top),
                    ],
                  ),
                ),
              ),
            ),
            // The effects, over the content and under the glass.
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: line + _Bars.topReach,
              child: AnimatedBuilder(
                animation: Listenable.merge(<Listenable>[
                  _topShown,
                  _topLook,
                  _blurOn,
                ]),
                builder: (BuildContext context, _) => ScrollEdgeEffect(
                  edge: line,
                  barAbove: true,
                  blur: _topShown.value * _blurOn.value,
                  black: _topLook.black * _topShown.value,
                  wash: _topLook.wash * _topShown.value,
                  washColor: background,
                ),
              ),
            ),
            if (hasBottom)
              Positioned(
                left: 0,
                right: 0,
                top: bottomLine - _Bars.bottomReach,
                bottom: 0,
                child: AnimatedBuilder(
                  animation: Listenable.merge(<Listenable>[
                    _bottomShown,
                    _bottomLook,
                  ]),
                  builder: (BuildContext context, _) => ScrollEdgeEffect(
                    edge: _Bars.bottomReach,
                    barAbove: false,
                    blur: 0,
                    black: _bottomLook.black * _bottomShown.value,
                    wash: _bottomLook.wash * _bottomShown.value,
                    washColor: background,
                  ),
                ),
              ),
            // UIKit's bar takes the touches over it.
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: line,
              child: const _TouchBlocker(),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: top,
              height: _Bars.platter,
              child: _navigationBar(),
            ),
            if (widget.toolbar.isNotEmpty)
              Positioned(
                left: _Bars.toolSide,
                right: _Bars.toolSide,
                top: barTop,
                height: _Bars.toolHeight,
                child: _Toolbar(items: widget.toolbar),
              ),
            if (_hasSearch)
              Positioned(
                left: _Bars.toolSide,
                right: _Bars.toolSide,
                top: barTop,
                height: _Bars.toolHeight,
                child: _SearchBar(
                  controller: _search,
                  focusNode: _searchFocus,
                  placeholder: widget.searchPlaceholder,
                  focused: _searching,
                  onChanged: widget.onSearchChanged,
                  onSubmitted: widget.onSearchSubmitted,
                  onClose: _closeSearch,
                ),
              ),
          ],
        );
        // The status bar turns light over the effect's dark look, as UIKit's.
        return AnimatedBuilder(
          animation: Listenable.merge(<Listenable>[_topShown, _topLook]),
          builder: (BuildContext context, Widget? child) =>
              AnnotatedRegion<SystemUiOverlayStyle>(
                value: _titleDark
                    ? SystemUiOverlayStyle.light
                    : SystemUiOverlayStyle.dark,
                child: child!,
              ),
          child: page,
        );
      },
    );
  }

  void _recordAreas(Size size, double line, double bottomLine, bool bottom) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final RenderObject? box = context.findRenderObject();
      if (box is! RenderBox || !box.hasSize) {
        return;
      }
      final Offset origin = box.localToGlobal(Offset.zero);
      _topArea = Rect.fromLTWH(
        origin.dx,
        origin.dy,
        size.width,
        line + _Bars.topReach,
      );
      _bottomArea = bottom
          ? Rect.fromLTWH(
              origin.dx,
              origin.dy + bottomLine - _Bars.bottomReach,
              size.width,
              size.height - bottomLine + _Bars.bottomReach,
            )
          : null;
    });
  }

  // The large title: in its row under the bar, moving up with the content.
  Widget _largeTitle(double top) {
    return Positioned(
      left: 0,
      right: 0,
      top: top + _Bars.navHeight,
      height: _Bars.largeRow,
      child: ValueListenableBuilder<double>(
        valueListenable: _offset,
        // It moves with the content, and hides once it has collapsed into
        // the bar (scrolled its row's height).
        builder: (BuildContext context, double offset, Widget? child) =>
            AnimatedOpacity(
              opacity: offset >= _Bars.largeRow ? 0 : 1,
              duration: const Duration(milliseconds: 150),
              child: Transform.translate(
                offset: Offset(0, -offset),
                child: child,
              ),
            ),
        child: Builder(
          builder: (BuildContext context) {
            final bool dark = _systemDark;
            return Padding(
              padding: const EdgeInsetsDirectional.only(
                start: _Bars.navSide,
                end: _Bars.navSide,
                top: _Bars.largeTop,
              ),
              child: Align(
                alignment: AlignmentDirectional.topStart,
                child: Text(
                  widget.title!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _Bars.large.copyWith(
                    color: dark
                        ? const Color(0xFFFFFFFF)
                        : const Color(0xFF000000),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // The title's look: the system's, or the effect's while it shows.
  bool get _titleDark =>
      _systemDark || (_topShown.value > 0.5 && _topLook.black > 0.125);

  Widget _navigationBar() {
    final List<Widget> leading = <Widget>[
      if (widget.onBack != null)
        _BackButton(onPressed: widget.onBack!, history: _history),
      for (final List<GlassBarItem> group in _groups(widget.leading))
        _NavPlatter(items: group),
    ];
    final List<Widget> trailing = <Widget>[
      for (final List<GlassBarItem> group in _groups(widget.actions))
        _NavPlatter(items: group),
    ];
    final String? title = widget.title;
    final Widget bar = GlassGroup(
      child: CustomMultiChildLayout(
        delegate: _NavLayout(textDirection: Directionality.of(context)),
        children: <Widget>[
          LayoutId(id: _NavSlot.leading, child: _spaced(leading)),
          LayoutId(id: _NavSlot.trailing, child: _spaced(trailing)),
          if (title != null)
            LayoutId(
              id: _NavSlot.title,
              child: ValueListenableBuilder<double>(
                valueListenable: _offset,
                builder: (BuildContext context, double offset, _) {
                  // With a large title, the bar's title shows once the
                  // large one has scrolled under the bar.
                  // With a large title, the bar's title waits 15pt low and
                  // unseen, and rises in once the large one has collapsed
                  // (scrolled its row's height), as UIKit's.
                  final bool shown =
                      !widget.largeTitle || offset >= _Bars.largeRow;
                  return AnimatedSlide(
                    offset: Offset(0, shown ? 0 : 15 / 22.67),
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOutCubic,
                    child: AnimatedOpacity(
                      opacity: shown ? 1 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: AnimatedBuilder(
                        animation: Listenable.merge(<Listenable>[
                          _topShown,
                          _topLook,
                        ]),
                        builder: (BuildContext context, _) => Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _Bars.title.copyWith(
                            color: _titleDark
                                ? const Color(0xFFFFFFFF)
                                : const Color(0xFF000000),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
    // While searching, the bar steps aside.
    return AnimatedBuilder(
      animation: _searching,
      builder: (BuildContext context, Widget? child) => IgnorePointer(
        ignoring: _searching.value > 0.5,
        child: Opacity(opacity: 1 - _searching.value, child: child),
      ),
      child: bar,
    );
  }

  static Widget _spaced(List<Widget> platters) => Row(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      for (final (int i, Widget p) in platters.indexed) ...<Widget>[
        if (i > 0) const SizedBox(width: _Bars.gap),
        p,
      ],
    ],
  );
}

/// UIKit's grouping: icons side by side share one platter; a label or a
/// prominent item has one of its own; a space splits groups.
List<List<GlassBarItem>> _groups(List<GlassBarItem> items) {
  final List<List<GlassBarItem>> groups = <List<GlassBarItem>>[];
  var current = <GlassBarItem>[];
  void flush() {
    if (current.isNotEmpty) {
      groups.add(current);
      current = <GlassBarItem>[];
    }
  }

  for (final GlassBarItem item in items) {
    if (item.isSpace) {
      flush();
    } else if (item.prominent || item.icon == null) {
      flush();
      groups.add(<GlassBarItem>[item]);
    } else {
      current.add(item);
    }
  }
  flush();
  return groups;
}

class _TouchBlocker extends StatelessWidget {
  const _TouchBlocker();

  @override
  Widget build(BuildContext context) =>
      const AbsorbPointer(child: SizedBox.expand());
}

enum _NavSlot { leading, trailing, title }

/// The bar: leading items from the start, trailing ones from the end, 20pt
/// in; the title centered on the bar, moved aside (or cut short) where it
/// would meet them.
class _NavLayout extends MultiChildLayoutDelegate {
  _NavLayout({required this.textDirection});

  final TextDirection textDirection;

  @override
  void performLayout(Size size) {
    final bool rtl = textDirection == TextDirection.rtl;
    final BoxConstraints loose = BoxConstraints.loose(size);
    final Size lead = layoutChild(_NavSlot.leading, loose);
    final Size trail = layoutChild(_NavSlot.trailing, loose);
    final double leadX = rtl
        ? size.width - _Bars.navSide - lead.width
        : _Bars.navSide;
    final double trailX = rtl
        ? _Bars.navSide
        : size.width - _Bars.navSide - trail.width;
    positionChild(
      _NavSlot.leading,
      Offset(leadX, (size.height - lead.height) / 2),
    );
    positionChild(
      _NavSlot.trailing,
      Offset(trailX, (size.height - trail.height) / 2),
    );
    if (hasChild(_NavSlot.title)) {
      final double start =
          _Bars.navSide + (lead.width > 0 ? lead.width + _Bars.gap : 0);
      final double end =
          size.width -
          _Bars.navSide -
          (trail.width > 0 ? trail.width + _Bars.gap : 0);
      final double left = rtl ? size.width - end : start;
      final double right = rtl ? size.width - start : end;
      final double room = math.max(0, right - left);
      final Size title = layoutChild(
        _NavSlot.title,
        BoxConstraints(maxWidth: room, maxHeight: size.height),
      );
      final double centered = (size.width - title.width) / 2;
      final double x = centered.clamp(
        left,
        math.max(left, right - title.width),
      );
      positionChild(
        _NavSlot.title,
        Offset(x, (size.height - title.height) / 2),
      );
    }
  }

  @override
  bool shouldRelayout(_NavLayout oldDelegate) =>
      oldDelegate.textDirection != textDirection;
}

Color _tintOf(BuildContext context, GlassBarItem item) =>
    item.tint ??
    GlassTabBarStyle.resolve(
      GlassTabBarStyle.systemBlue,
      dark: MediaQuery.platformBrightnessOf(context) == Brightness.dark,
    );

/// UIKit's back button: a 44pt glass circle with the back chevron.
class _BackButton extends StatelessWidget {
  const _BackButton({required this.onPressed, required this.history});

  final VoidCallback onPressed;

  /// The pages under this one, for UIKit's long press on the back button.
  final List<GlassMenuItem> Function() history;

  @override
  Widget build(BuildContext context) {
    // No pages under this one (or none with a title): a plain back button.
    if (history().isEmpty) {
      return _backButton();
    }
    final bool dark =
        MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    return GlassMenuAnchor(
      longPress: true,
      items: history,
      sourceContent: Center(
        child: CustomPaint(
          size: const Size(16.33, 23),
          painter: _GlyphPainter(
            _chevron,
            dark ? const Color(0xFFFFFFFF) : const Color(0xFF000000),
          ),
        ),
      ),
      child: _backButton(),
    );
  }

  Widget _backButton() {
    return Semantics(
      button: true,
      label: 'Back',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: SizedBox.square(
          dimension: _Bars.platter,
          child: Glass(
            interactive: true,
            child: _Pressable(
              enabled: true,
              builder: (BuildContext context, double highlight) =>
                  GlassVibrantLabel(
                    glyph: _chevron,
                    glyphSize: const Size(16.33, 23),
                    style: _Bars.item,
                    pressFade: _Bars.pressFade,
                    strength: 1 - (1 - _Bars.navHighlight) * highlight,
                  ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlyphPainter extends CustomPainter {
  const _GlyphPainter(this.glyph, this.color);

  final GlassGlyph glyph;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) => glyph(canvas, size, color);

  @override
  bool shouldRepaint(_GlyphPainter old) =>
      old.glyph != glyph || old.color != color;
}

/// A navigation bar platter: one group's glass, 44pt tall.
class _NavPlatter extends StatelessWidget {
  const _NavPlatter({required this.items});

  final List<GlassBarItem> items;

  @override
  Widget build(BuildContext context) {
    final GlassBarItem first = items.first;
    final bool prominent = first.prominent;
    final bool lone = items.length == 1 && first.icon != null;
    final List<Widget> children = <Widget>[
      for (final (int i, GlassBarItem item) in items.indexed) ...<Widget>[
        if (i > 0) const SizedBox(width: _Bars.navItemGap),
        _menuAnchor(
          context,
          item,
          anchored: !lone,
          child: _ItemButton(
            item: item,
            highlight: _Bars.navHighlight,
            height: _Bars.navItem,
            width: lone ? _Bars.navItem : null,
            iconSide: _Bars.navIconSide,
            textSide: _Bars.navTextSide,
          ),
        ),
      ],
    ];
    return _menuAnchor(
      context,
      first,
      anchored: lone,
      child: SizedBox(
        height: _Bars.platter,
        width: lone ? _Bars.platter : null,
        child: Glass(
          interactive: true,
          tint: prominent && first.isEnabled ? _tintOf(context, first) : null,
          child: Padding(
            padding: const EdgeInsets.all(_Bars.navInset),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: children,
            ),
          ),
        ),
      ),
    );
  }
}

/// [child], opening [item]'s menu when [anchored] and it has one (as
/// UIKit's, out of the item's glass: its platter when alone on it, else
/// its slot).
Widget _menuAnchor(
  BuildContext context,
  GlassBarItem item, {
  required bool anchored,
  required Widget child,
}) {
  final List<GlassMenuItem>? menu = item.menu;
  if (!anchored || menu == null) {
    return child;
  }
  final bool dark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
  final Color color = item.prominent || dark
      ? const Color(0xFFFFFFFF)
      : const Color(0xFF000000);
  return GlassMenuAnchor(
    items: () => menu,
    sourceContent: Center(
      child: item.icon != null
          ? Icon(item.icon, size: _Bars.iconSize, color: color)
          : Text(
              item.label ?? '',
              maxLines: 1,
              style: (item.prominent ? _Bars.prominentItem : _Bars.item)
                  .copyWith(color: color),
            ),
    ),
    child: child,
  );
}

/// One item: its icon or label, drawn vibrantly on the glass, and its tap.
class _ItemButton extends StatelessWidget {
  const _ItemButton({
    required this.item,
    required this.height,
    required this.iconSide,
    required this.textSide,
    required this.highlight,
    this.width,
  });

  final GlassBarItem item;
  final double height;
  final double? width;
  final double iconSide;
  final double textSide;

  /// How strongly the item shows while pressed.
  final double highlight;

  @override
  Widget build(BuildContext context) {
    final bool enabled = item.isEnabled;
    final bool icon = item.icon != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: item.semanticLabel ?? item.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: item.onPressed,
        child: SizedBox(
          height: height,
          width: width,
          child: _Pressable(
            enabled: enabled,
            builder: (BuildContext context, double pressed) =>
                GlassVibrantLabel(
                  icon: item.icon,
                  label: icon ? null : item.label,
                  style: item.prominent ? _Bars.prominentItem : _Bars.item,
                  iconBox: _Bars.iconBox,
                  iconSize: _Bars.iconSize,
                  fixedBox: true,
                  side: width != null ? 0 : (icon ? iconSide : textSide),
                  enabled: enabled,
                  onTint: item.prominent && enabled,
                  pressFade: _Bars.pressFade,
                  strength: 1 - (1 - highlight) * pressed,
                ),
          ),
        ),
      ),
    );
  }
}

/// An item's own highlight under the finger: 0 to 1, in 80ms, out in 250ms.
class _Pressable extends StatefulWidget {
  const _Pressable({required this.enabled, required this.builder});

  final bool enabled;
  final Widget Function(BuildContext context, double pressed) builder;

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pressed = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 80),
    reverseDuration: const Duration(milliseconds: 250),
  );

  @override
  void dispose() {
    _pressed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: widget.enabled ? (_) => _pressed.forward() : null,
      onPointerUp: (_) => _pressed.reverse(),
      onPointerCancel: (_) => _pressed.reverse(),
      child: AnimatedBuilder(
        animation: _pressed,
        builder: (BuildContext context, _) =>
            widget.builder(context, _pressed.value),
      ),
    );
  }
}

/// The toolbar: groups of items, each on glass 48pt tall, spread by
/// spaces, or centered together when there are none.
class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.items});

  final List<GlassBarItem> items;

  @override
  Widget build(BuildContext context) {
    // Segments: the items between spaces, each a row of glass groups.
    final List<List<GlassBarItem>> segments = <List<GlassBarItem>>[
      <GlassBarItem>[],
    ];
    for (final GlassBarItem item in items) {
      if (item.isSpace) {
        segments.add(<GlassBarItem>[]);
      } else {
        segments.last.add(item);
      }
    }
    final List<Widget> children = <Widget>[
      for (final (int i, List<GlassBarItem> segment) in segments.indexed)
        LayoutId(
          id: i,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (final (int j, List<GlassBarItem> group) in _groups(
                segment,
              ).indexed) ...<Widget>[
                if (j > 0) const SizedBox(width: _Bars.gap),
                _ToolGroup(items: group),
              ],
            ],
          ),
        ),
    ];
    return GlassGroup(
      child: CustomMultiChildLayout(
        delegate: _ToolbarLayout(
          count: segments.length,
          textDirection: Directionality.of(context),
        ),
        children: children,
      ),
    );
  }
}

/// UIKit's toolbar: with no spaces, everything centered; with spaces, the
/// first segment at the start, the last at the end, and those between with
/// their centers evenly across the bar (one alone in its middle), kept
/// clear of their neighbors.
class _ToolbarLayout extends MultiChildLayoutDelegate {
  _ToolbarLayout({required this.count, required this.textDirection});

  final int count;
  final TextDirection textDirection;

  @override
  void performLayout(Size size) {
    final List<Size> sizes = <Size>[
      for (var i = 0; i < count; i++)
        layoutChild(i, BoxConstraints.loose(size)),
    ];
    final List<double> xs = List<double>.filled(count, 0);
    if (count == 1) {
      xs[0] = (size.width - sizes[0].width) / 2;
    } else {
      xs[0] = 0;
      xs[count - 1] = size.width - sizes[count - 1].width;
      var floor = sizes[0].width;
      for (var i = 1; i < count - 1; i++) {
        final double center = size.width * i / (count - 1);
        xs[i] = math.max(floor, center - sizes[i].width / 2);
        floor = xs[i] + sizes[i].width;
      }
    }
    for (var i = 0; i < count; i++) {
      final double x = textDirection == TextDirection.rtl
          ? size.width - xs[i] - sizes[i].width
          : xs[i];
      positionChild(i, Offset(x, (size.height - sizes[i].height) / 2));
    }
  }

  @override
  bool shouldRelayout(_ToolbarLayout oldDelegate) =>
      oldDelegate.count != count || oldDelegate.textDirection != textDirection;
}

/// A toolbar group's glass: a 48pt circle for a lone icon, else a capsule
/// of slots.
class _ToolGroup extends StatelessWidget {
  const _ToolGroup({required this.items});

  final List<GlassBarItem> items;

  @override
  Widget build(BuildContext context) {
    final GlassBarItem first = items.first;
    final bool lone = items.length == 1 && first.icon != null;
    return _menuAnchor(
      context,
      first,
      anchored: lone,
      child: SizedBox(
        height: _Bars.toolHeight,
        width: lone ? _Bars.toolHeight : null,
        child: Glass(
          interactive: true,
          tint: first.prominent && first.isEnabled
              ? _tintOf(context, first)
              : null,
          child: lone
              ? _ItemButton(
                  item: first,
                  highlight: _Bars.toolHighlight,
                  height: _Bars.toolHeight,
                  width: _Bars.toolHeight,
                  iconSide: 0,
                  textSide: 0,
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    for (final (int i, GlassBarItem item)
                        in items.indexed) ...<Widget>[
                      if (i > 0) const SizedBox(width: _Bars.slotGap),
                      Padding(
                        padding: const EdgeInsets.all(_Bars.toolInset),
                        child: _menuAnchor(
                          context,
                          item,
                          anchored: true,
                          child: _ItemButton(
                            item: item,
                            highlight: _Bars.toolHighlight,
                            height: _Bars.toolHeight - 2 * _Bars.toolInset,
                            iconSide: _Bars.toolIconSide,
                            textSide: _Bars.toolTextSide,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}

/// UIKit's search field in the toolbar's place: a glass capsule with the
/// magnifier and the text; focused, it makes room for a close circle.
class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.focusNode,
    required this.placeholder,
    required this.focused,
    required this.onClose,
    this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String placeholder;
  final Animation<double> focused;
  final VoidCallback onClose;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: focused,
      builder: (BuildContext context, _) {
        final double t = focused.value;
        return LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final double full = constraints.maxWidth;
            final double room = _Bars.toolHeight + _Bars.closeGap;
            return GlassGroup(
              child: Stack(
                children: <Widget>[
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: full - room * t,
                    child: Glass(
                      interactive: true,
                      child: Padding(
                        padding: const EdgeInsets.all(_Bars.toolInset),
                        child: _SearchField(
                          controller: controller,
                          focusNode: focusNode,
                          placeholder: placeholder,
                          onChanged: onChanged,
                          onSubmitted: onSubmitted,
                        ),
                      ),
                    ),
                  ),
                  if (t > 0)
                    PositionedDirectional(
                      end: 0,
                      top: 0,
                      width: _Bars.toolHeight,
                      height: _Bars.toolHeight,
                      child: Opacity(
                        opacity: t,
                        child: Semantics(
                          button: true,
                          label: 'Close',
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: onClose,
                            child: Glass(
                              interactive: true,
                              visible: t > 0.5,
                              child: const GlassVibrantLabel(
                                glyph: _cross,
                                glyphSize: Size(16.7, 16.7),
                                style: _Bars.item,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// The field's content: the magnifier 13pt from its leading end, the text
/// 41.67pt from it, 17pt (the tab bar's search field's metrics).
class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.placeholder,
    this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String placeholder;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final bool dark =
        glassIsDarkOf(context) ??
        MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    final Color text = dark ? const Color(0xFFFFFFFF) : const Color(0xFF000000);
    // UIKit's toolbar search field (iOS 26.5, over white): the magnifier in
    // the label color, 2pt strokes; the placeholder a neutral gray (114).
    final Color secondary = dark
        ? const Color(0xC2EBEBF5)
        : const Color(0x8C000000);
    return Row(
      children: <Widget>[
        const SizedBox(width: 13),
        SizedBox(
          width: 20.67,
          child: Center(
            child: IconTheme(
              data: IconThemeData(color: text),
              child: const BarGlyph.field(size: 16.5, stroke: 2),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: CupertinoTextField.borderless(
            controller: controller,
            focusNode: focusNode,
            placeholder: placeholder,
            padding: EdgeInsets.zero,
            style: TextStyle(fontSize: 17, color: text),
            placeholderStyle: TextStyle(fontSize: 17, color: secondary),
            textInputAction: TextInputAction.search,
            onChanged: onChanged,
            onSubmitted: onSubmitted,
          ),
        ),
        const SizedBox(width: 12),
      ],
    );
  }
}

/// UIKit's back chevron (SF chevron.backward in the bar, measured on iOS
/// 26.5): two 2.5pt round-capped strokes at 45 degrees meeting at a tip,
/// in its 16.33 x 23 box.
void _chevron(Canvas canvas, Size size, Color color) {
  final Path path = Path()
    ..moveTo(10.53, 3.58)
    ..lineTo(2.58, 11.66)
    ..lineTo(10.53, 19.73);
  canvas.drawPath(
    path,
    Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round,
  );
}

/// The search field's close cross: the tab bar's (16.7pt, 1.7pt strokes).
void _cross(Canvas canvas, Size size, Color color) {
  final paint = Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.7
    ..strokeCap = StrokeCap.round;
  const double a = 0.85, b = 16.7 - 0.85;
  canvas
    ..drawLine(const Offset(a, a), const Offset(b, b), paint)
    ..drawLine(const Offset(b, a), const Offset(a, b), paint);
}

/// A scroll-edge effect's look, as UIKit picks it from the content's mean
/// luma (sRGB) under the effect, animating from one look to the next.
///
/// With the system light: a wash toward the page's background (0.8) over
/// light content, and black at 0.25 below 0.675 (gray 0.65 and the blocks
/// pattern at 0.662 were dark, gray 0.7 light). With it dark: never black,
/// a wash of 0.85 below 0.35, 0.6 up to 0.85, and 0.3 above (iOS 26.5).
class _EdgeLook extends ChangeNotifier {
  _EdgeLook(TickerProvider vsync)
    : _change = AnimationController(
        vsync: vsync,
        duration: const Duration(milliseconds: 300),
      ) {
    _change.addListener(notifyListeners);
  }

  final AnimationController _change;
  int _level = 0;
  bool _dark = false;
  ({double black, double wash}) _from = _light[0], _to = _light[0];

  static const List<({double black, double wash})> _light =
      <({double black, double wash})>[
        (black: 0, wash: 0.8),
        (black: 0.25, wash: 0),
      ];
  static const List<({double black, double wash})> _darkLooks =
      <({double black, double wash})>[
        (black: 0, wash: 0.85),
        (black: 0, wash: 0.6),
        (black: 0, wash: 0.3),
      ];

  double get _t => Curves.easeInOut.transform(_change.value);
  double get black => _from.black + (_to.black - _from.black) * _t;
  double get wash => _from.wash + (_to.wash - _from.wash) * _t;

  void reset({required bool dark}) {
    _dark = dark;
    _level = dark ? 1 : 0;
    _from = _to = (dark ? _darkLooks : _light)[_level];
    _change.value = 1;
  }

  void sample(double luma, {required bool dark}) {
    final int level = dark
        ? (luma < 0.35
              ? 0
              : luma < 0.85
              ? 1
              : 2)
        : (_level == 1 ? (luma > 0.69 ? 0 : 1) : (luma < 0.675 ? 1 : 0));
    _go(level, dark);
  }

  void _go(int level, bool dark) {
    if (level == _level && dark == _dark) {
      return;
    }
    _from = (black: black, wash: wash);
    _level = level;
    _dark = dark;
    _to = (dark ? _darkLooks : _light)[level];
    _change.forward(from: 0);
  }

  @override
  void dispose() {
    _change.dispose();
    super.dispose();
  }
}
