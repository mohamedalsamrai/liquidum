import 'dart:math' as math;

import 'package:flutter/cupertino.dart'
    show CupertinoDynamicColor, CupertinoTheme;
import 'package:flutter/widgets.dart';

import 'glass_backdrop.dart';
import 'tab_bar/decoration.dart';
import 'tab_bar/item.dart';
import 'tab_bar/tab_bar.dart';

/// A tab of a [GlassTabScaffold]: its icon, label and page.
///
/// ```dart
/// GlassTab(icon: CupertinoIcons.house_fill, label: 'Home', page: HomePage())
/// ```
@immutable
class GlassTab {
  const GlassTab({
    required IconData icon,
    IconData? selectedIcon,
    required this.label,
    required this.page,
    this.badge,
    this.color,
  }) : _iconData = icon,
       _selectedIconData = selectedIcon,
       _icon = null,
       _selectedIcon = null,
       tintIcon = true;

  /// A tab whose icons are widgets: an SVG, an image, any widget. The bar
  /// uses them for their shape and colors them itself, whatever colors they
  /// have; turn off [tintIcon] for icons that keep their own colors, such as
  /// a profile photo.
  const GlassTab.custom({
    required Widget this._icon,
    this._selectedIcon,
    required this.label,
    required this.page,
    this.badge,
    this.color,
    this.tintIcon = true,
  }) : _iconData = null,
       _selectedIconData = null;

  final IconData? _iconData;
  final IconData? _selectedIconData;
  final Widget? _icon;
  final Widget? _selectedIcon;

  final String label;

  /// The tab's first page.
  final Widget page;

  /// A badge on the icon, such as a count. None when null.
  final String? badge;

  /// This tab's selected color, instead of [GlassTabScaffold.selectedColor].
  final Color? color;

  /// Whether the bar colors the icon (see [GlassTab.custom]).
  final bool tintIcon;

  GlassTabItem get _item => GlassTabItem(
    icon: _icon ?? Icon(_iconData),
    selectedIcon:
        _selectedIcon ??
        (_selectedIconData == null ? null : Icon(_selectedIconData)),
    label: label,
    badge: badge,
    selectedColor: color,
    tintIcon: tintIcon,
  );
}

/// An app's tabs under an iOS 26 glass tab bar.
///
/// ```dart
/// GlassTabScaffold(
///   tabs: [
///     GlassTab(icon: CupertinoIcons.house_fill, label: 'Home', page: HomePage()),
///     GlassTab(icon: CupertinoIcons.bell_fill, label: 'Alerts', badge: '3', page: AlertsPage()),
///   ],
/// )
/// ```
///
/// Everything else is done for you, as in an iOS app:
/// - the bar floats over the pages, which extend under it, and its glass
///   adapts to them;
/// - each tab keeps its page (and its scroll position and state) while
///   another is shown;
/// - each tab has its own navigator, so `Navigator.push` from a page stays
///   in its tab, under the bar, and the back button pops it first;
/// - selecting the selected tab again goes back to its first page;
/// - the pages' [MediaQueryData.padding] includes the bar, so a [SafeArea]
///   or a scroll view keeps their content clear of it at the end;
/// - in a right-to-left app, the first tab is on the right.
///
/// To switch tabs from code: `GlassTabScaffold.of(context).index = 1`.
class GlassTabScaffold extends StatefulWidget {
  const GlassTabScaffold({
    super.key,
    required this.tabs,
    this.selectedColor,
    this.unselectedColor,
    this.badgeColor,
    this.brightness,
    this.adaptive = true,
    this.labelStyle,
    this.glassColor,
    this.indicatorColor,
    this.lensColor,
    this.glass,
    this.indicator,
    this.lens,
    this.backgroundColor,
    this.barMargin,
    this.barPadding,
    this.initialIndex = 0,
    this.onTabChanged,
    this.controller,
  });

  final List<GlassTab> tabs;

  /// The selected tab's color. Defaults to the system blue.
  final Color? selectedColor;

  /// The other tabs' color. By default they take their colors from the
  /// glass under them, as in UIKit (whose iOS 26 bar has no such setting).
  final Color? unselectedColor;

  /// Badges' color. Defaults to the system red.
  final Color? badgeColor;

  /// Forces the bar's light or dark appearance. Defaults to the system's.
  final Brightness? brightness;

  /// Whether the bar turns dark over dark pages and light over light ones,
  /// as UIKit's does.
  final bool adaptive;

  /// Merged into the labels' style, for example to set a font family.
  final TextStyle? labelStyle;

  /// Tints the bar's glass, as iOS tints glass (`UIGlassEffect.tintColor`).
  /// The color's alpha sets how strongly. None by default.
  final Color? glassColor;

  /// Tints the glass under the selected tab at rest. None by default.
  final Color? indicatorColor;

  /// Tints the lens the selection lifts into while the bar is pressed or
  /// dragged. None by default (clear, as in UIKit).
  final Color? lensColor;

  /// The bar's glass decorated: a tint or a [LinearGradient], drop shadows
  /// (in place of UIKit's) and inner shadows, like a [BoxDecoration].
  /// [glassColor] is short for its color.
  final GlassDecoration? glass;

  /// The glass under the selected tab at rest, decorated the same way.
  final GlassDecoration? indicator;

  /// The lens while the selection moves, decorated the same way.
  final GlassDecoration? lens;

  /// Painted behind the pages. Defaults to the theme's background.
  final Color? backgroundColor;

  /// Space between the bar and the screen's left, right and bottom edges
  /// (its top is not used), for example
  /// `EdgeInsets.fromLTRB(16, 0, 16, 30)`. Directional insets follow the
  /// app's direction. Defaults to UIKit's: 21pt from each, clear of the
  /// system's insets (on iPhones with a home indicator, the bar sits 13pt
  /// into the 34pt safe area). With up to three tabs, the bar is centered
  /// between the side margins.
  final EdgeInsetsGeometry? barMargin;

  /// Space inside the bar around its tabs, for example `EdgeInsets.all(12)`:
  /// the bar grows with it, the tabs keep their height. Defaults to UIKit's
  /// 4pt all round (a 62pt bar).
  final EdgeInsetsGeometry? barPadding;

  /// The tab shown first.
  final int initialIndex;

  /// Called with the tab's index whenever another tab is selected.
  final ValueChanged<int>? onTabChanged;

  /// To read or switch the selected tab from outside the scaffold. Pages
  /// can use [GlassTabScaffold.of] instead.
  final GlassTabController? controller;

  /// The controller of the closest [GlassTabScaffold].
  static GlassTabController of(BuildContext context) {
    final _GlassTabScope? scope = context
        .getInheritedWidgetOfExactType<_GlassTabScope>();
    assert(scope != null, 'No GlassTabScaffold above this context.');
    return scope!.controller;
  }

  @override
  State<GlassTabScaffold> createState() => _GlassTabScaffoldState();
}

/// Which tab of a [GlassTabScaffold] is selected. Setting [index] switches
/// tabs.
class GlassTabController extends ChangeNotifier {
  GlassTabController({int initialIndex = 0}) : _index = initialIndex;

  int get index => _index;
  int _index;
  set index(int value) {
    if (value != _index) {
      _index = value;
      notifyListeners();
    }
  }
}

class _GlassTabScaffoldState extends State<GlassTabScaffold> {
  GlassTabController? _own;
  GlassTabController get _controller =>
      widget.controller ??
      (_own ??= GlassTabController(initialIndex: widget.initialIndex));

  // Tabs whose page has been built, and is kept.
  final Set<int> _built = <int>{};
  final List<GlobalKey<NavigatorState>> _navigators =
      <GlobalKey<NavigatorState>>[];
  final List<HeroController> _heroes = <HeroController>[];

  int get _index => _controller.index.clamp(0, widget.tabs.length - 1);

  @override
  void initState() {
    super.initState();
    _controller.addListener(_changed);
  }

  @override
  void didUpdateWidget(GlassTabScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      (oldWidget.controller ?? _own)?.removeListener(_changed);
      if (widget.controller != null) {
        _own?.dispose();
        _own = null;
      }
      _controller.addListener(_changed);
    }
    _built.removeWhere((int i) => i >= widget.tabs.length);
  }

  @override
  void dispose() {
    _controller.removeListener(_changed);
    _own?.dispose();
    for (final HeroController hero in _heroes) {
      hero.dispose();
    }
    super.dispose();
  }

  void _changed() {
    setState(() {});
    widget.onTabChanged?.call(_index);
  }

  @override
  Widget build(BuildContext context) {
    assert(widget.tabs.isNotEmpty, 'A GlassTabScaffold needs tabs.');
    while (_navigators.length < widget.tabs.length) {
      _navigators.add(GlobalKey<NavigatorState>());
      _heroes.add(HeroController());
    }
    final MediaQueryData media = MediaQuery.of(context);
    final EdgeInsets inset = media.viewPadding;
    // UIKit floats the bar 21pt from the sides and bottom of the screen (on
    // iPhones with a home indicator, 13pt into the 34pt safe area), clear of
    // wider system insets.
    final EdgeInsets margin =
        widget.barMargin?.resolve(Directionality.of(context)) ??
        EdgeInsets.fromLTRB(
          21 + inset.left,
          0,
          21 + inset.right,
          math.max(21, inset.bottom - 13),
        );
    final double barSpace =
        margin.bottom + GlassTabBar.heightWith(widget.barPadding);
    final int index = _index;
    _built.add(index);

    return _GlassTabScope(
      controller: _controller,
      tabs: widget.tabs,
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: GlassBackdrop(
              child: ColoredBox(
                color:
                    widget.backgroundColor ??
                    CupertinoDynamicColor.resolve(
                      CupertinoTheme.of(context).scaffoldBackgroundColor,
                      context,
                    ),
                child: MediaQuery(
                  data: media.copyWith(
                    padding: media.padding.copyWith(
                      bottom: math.max(media.padding.bottom, barSpace),
                    ),
                    viewPadding: inset.copyWith(
                      bottom: math.max(inset.bottom, barSpace),
                    ),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      for (var i = 0; i < widget.tabs.length; i++)
                        _TabPage(
                          active: i == index,
                          child: _built.contains(i)
                              ? _page(i, i == index)
                              : null,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: margin.left,
            right: margin.right,
            bottom: margin.bottom,
            // Centered: with up to three tabs, the bar is only as wide as its
            // tabs, as UIKit's.
            child: Center(
              child: GlassTabBar(
                items: <GlassTabItem>[
                  for (final GlassTab t in widget.tabs) t._item,
                ],
                selectedIndex: index,
                onSelected: (int i) => _controller.index = i,
                onReselected: (int i) => _navigators[i].currentState?.popUntil(
                  (Route<dynamic> route) => route.isFirst,
                ),
                selectedColor: widget.selectedColor,
                unselectedColor: widget.unselectedColor,
                badgeColor: widget.badgeColor,
                brightness: widget.brightness,
                adaptive: widget.adaptive,
                labelStyle: widget.labelStyle,
                glassColor: widget.glassColor,
                indicatorColor: widget.indicatorColor,
                lensColor: widget.lensColor,
                glass: widget.glass,
                indicator: widget.indicator,
                lens: widget.lens,
                padding: widget.barPadding,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // A tab's navigator, whose first route is the tab's page.
  Widget _page(int i, bool active) {
    final GlobalKey<NavigatorState> key = _navigators[i];
    return NavigatorPopHandler<Object?>(
      enabled: active,
      onPopWithResult: (_) => key.currentState?.maybePop(),
      child: Navigator(
        key: key,
        observers: <NavigatorObserver>[_heroes[i]],
        onGenerateRoute: (RouteSettings settings) => PageRouteBuilder<void>(
          settings: settings,
          pageBuilder: (BuildContext context, _, _) => _TabRoot(index: i),
        ),
      ),
    );
  }
}

/// One tab's page: shown, animated, focusable and flying heroes only while
/// the tab is selected.
class _TabPage extends StatelessWidget {
  const _TabPage({required this.active, required this.child});

  final bool active;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Offstage(
      offstage: !active,
      child: TickerMode(
        enabled: active,
        child: ExcludeFocus(
          excluding: !active,
          child: HeroMode(enabled: active, child: child ?? const SizedBox()),
        ),
      ),
    );
  }
}

/// A tab's first page, from the scaffold's current tabs, so that it follows
/// the scaffold's rebuilds.
class _TabRoot extends StatelessWidget {
  const _TabRoot({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    final List<GlassTab> tabs = context
        .dependOnInheritedWidgetOfExactType<_GlassTabScope>()!
        .tabs;
    return index < tabs.length ? tabs[index].page : const SizedBox();
  }
}

class _GlassTabScope extends InheritedWidget {
  const _GlassTabScope({
    required this.controller,
    required this.tabs,
    required super.child,
  });

  final GlassTabController controller;
  final List<GlassTab> tabs;

  @override
  bool updateShouldNotify(_GlassTabScope oldWidget) =>
      oldWidget.tabs != tabs || oldWidget.controller != controller;
}
