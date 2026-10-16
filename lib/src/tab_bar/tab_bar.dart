import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart' show CupertinoTextField;
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/services.dart' show TextInputAction;
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../glass_backdrop.dart';
import '../shader_program.dart';
import 'appearance.dart';
import 'glyphs.dart';
import 'decoration.dart';
import 'item.dart';
import 'minimize.dart';
import 'physics.dart';
import 'style.dart';
import 'tab_content.dart';
import 'tint.dart';

/// What [GlassTabBar] draws for its glass while it is being built up.
enum GlassTabBarDebugView {
  /// The glass: the bar's pass and the lens's pass over one shared backdrop
  /// capture (neutral placeholders until the optics are in).
  none,

  /// The glass field flat: platter, pill and lens silhouettes.
  field,

  /// The lens's surface normals as colors.
  normals,

  /// The sampling architecture made visible: the bar's glass hatched (so a
  /// pass reading rendered glass would show it), the lens pass marking what
  /// it shows from outside itself, an inspector with the capture both passes
  /// read, and the glass field, sampling region and finger drawn twice (by
  /// the shaders in capture pixels, and by the canvas in layout
  /// coordinates) so that any mismatch shows.
  sampling,
}

/// The optical stages of the glass, as bits of [GlassTabBar.debugOptics].
abstract final class GlassTabBarOptics {
  /// The lens's warp: samples pushed outward near its edge.
  static const int warp = 1;

  /// The lens's inner refraction, and its material's tone.
  static const int inner = 2;

  /// The lens's chromatic dispersion.
  static const int dispersion = 4;

  /// The platter's material (refraction, frost, color); without it, the
  /// backdrop is seen bare.
  static const int platter = 8;

  /// The resting selection's tint.
  static const int rest = 16;

  /// The lifted content: the selected tab grown and lensed by the lens.
  static const int content = 32;

  /// The lit rims of the platter and the lens.
  static const int rim = 64;

  /// The shadows of the platter and the lens.
  static const int shadow = 128;

  /// The press: the wash over the platter and the fingertip glow.
  static const int press = 256;

  static const int all = 511;
}

/// An iOS 26 tab bar: a glass platter holding the tabs, and a lens that
/// selects one. Press and slide to carry the lens between tabs; release to
/// select the tab under it.
///
/// The bar is 62pt high. As UIKit's, with four tabs or more it is as wide as
/// it is allowed to be, and with fewer it is only as wide as its tabs need
/// (274pt for three) when allowed to be narrower: center it. UIKit floats it
/// 21pt from the sides and bottom of the screen. It adapts to what is
/// behind it when that is wrapped in a [GlassBackdrop]. [GlassTabScaffold]
/// does all of this, and gives each tab its page.
///
/// In a right-to-left [Directionality], the first tab is on the right, as in
/// UIKit.
class GlassTabBar extends StatefulWidget {
  const GlassTabBar({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    this.onReselected,
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
    this.padding,
    this.search,
    this.accessory,
    this.minimized = false,
    this.onExpand,
    this.reduceTransparency = false,
    this.searchController,
    this.searchFocusNode,
    this.searchPlaceholder = 'Search',
    this.onSearchChanged,
    this.onSearchSubmitted,
    this.debugView = GlassTabBarDebugView.none,
    this.debugShareBackdrop = true,
    this.debugInspector,
    this.debugHold,
    this.debugHideContent = false,
    this.debugOptics = GlassTabBarOptics.all,
    this.debugLift,
  });

  /// Height of the bar, as on iOS 26.
  static const double height = 62;

  final List<GlassTabItem> items;

  /// The selected tab, by its index in [items].
  final int selectedIndex;

  /// Called with a tab's index when the finger lets go over another tab
  /// than the selected one. The bar shows it selected only once
  /// [selectedIndex] says so, and otherwise goes back.
  final ValueChanged<int> onSelected;

  /// Called with the selected tab's index when the finger lets go over it
  /// again, for example to scroll its page to the top.
  final ValueChanged<int>? onReselected;

  /// The selected tab's icon and label color, as `UITabBar.tintColor`.
  /// Defaults to the system blue.
  ///
  /// As UIKit does, the bar mixes it with the glass under the tab: it shows
  /// half of that glass plus this color, less half a unit in the light
  /// appearance. Over the resting selection that comes out close to the
  /// color itself. Dynamic colors (such as `CupertinoColors.systemPink`)
  /// resolve for the bar's own appearance.
  final Color? selectedColor;

  /// The other tabs' icon and label color. By default (null) they take
  /// UIKit's adaptive colors from the glass under them, which UIKit's iOS 26
  /// bar always uses (it ignores `unselectedItemTintColor`). When set, they
  /// are drawn in this color as it is.
  final Color? unselectedColor;

  /// Badges' color. Defaults to the system red.
  final Color? badgeColor;

  /// The appearance the bar starts from, as UIKit's
  /// `overrideUserInterfaceStyle`. Defaults to the platform's.
  final Brightness? brightness;

  /// Whether the bar turns dark over dark content and light over light
  /// content, as UIKit's does (it needs a [GlassBackdrop] under it). When
  /// false, it keeps [brightness].
  final bool adaptive;

  /// Merged into the labels' style (UIKit's: 10pt, semibold when selected
  /// and medium otherwise), for example to set a font family. Its color is
  /// ignored.
  final TextStyle? labelStyle;

  /// Tints the bar's glass, as `UIGlassEffect.tintColor` tints glass: the
  /// glass takes the color, deeper where it is darker (over dark content,
  /// or in the dark appearance) and as it is where it is white. The color's
  /// alpha sets how strongly: a translucent color lets the plain glass show
  /// through. None by default.
  final Color? glassColor;

  /// Tints the glass under the selected tab at rest, the same way. UIKit's
  /// is a gray tint of the glass (this is on top of it). None by default.
  final Color? indicatorColor;

  /// Tints the lens that the selection lifts into while the bar is pressed
  /// or dragged, the same way. UIKit's lens is clear. None by default.
  final Color? lensColor;

  /// The bar's glass decorated: a tint or a gradient, drop shadows (in place
  /// of UIKit's) and inner shadows. [glassColor] is short for its color.
  final GlassDecoration? glass;

  /// The selection at rest decorated the same way ([indicatorColor] is
  /// short for its color).
  final GlassDecoration? indicator;

  /// The lens, while the selection moves, decorated the same way
  /// ([lensColor] is short for its color).
  final GlassDecoration? lens;

  /// Space inside the bar around its tabs, as a box's padding: the bar grows
  /// with it, the tabs keep their 54pt height. Defaults to UIKit's 4pt all
  /// round (a 62pt bar). Directional padding follows the app's direction.
  ///
  /// The lens the selection lifts into still rises out of the bar as UIKit's
  /// does, 4pt past its top and bottom edges whatever the padding.
  final EdgeInsetsGeometry? padding;

  /// A search tab, as UIKit's `UISearchTab`: a glass circle of its own at
  /// the bar's trailing end, with the platter at its leading end (from three
  /// tabs on, the platter fills the room left). It is selected when
  /// [selectedIndex] is [items]' length: its icon then takes the selected
  /// color, and the platter shows no selection. Its icon defaults to a
  /// magnifying glass.
  final GlassTabItem? search;

  /// UIKit's bottom accessory (`UITabAccessory`), such as a now-playing
  /// control: a 48pt glass capsule 8pt above the bar, as wide as the bar,
  /// that moves into the bar's row when it minimizes. Its content is drawn
  /// as it is.
  final Widget? accessory;

  /// Whether the bar is minimized, as UIKit's minimizes on scrolling down
  /// (`tabBarMinimizeBehavior`): the platter collapses into a 48pt circle
  /// at its leading end showing the selected tab's icon, the search circle
  /// shrinks to 48pt, and the accessory sits between them. Animated with
  /// UIKit's springs.
  final bool minimized;

  /// Called when the minimized bar is tapped, for its owner to expand it.
  final VoidCallback? onExpand;

  /// The search field's text. With it, selecting the [search] tab opens the
  /// bar into a search field, as UIKit's does when the search tab's page has
  /// a search controller: the platter collapses into a circle with the last
  /// tab's icon (tap it to go back), and the search circle grows into a
  /// field. While the field has the keyboard it narrows for a close button,
  /// which ends the search's editing and clears it.
  final TextEditingController? searchController;

  /// The search field's focus, to open the keyboard from code. The bar
  /// makes its own when null.
  final FocusNode? searchFocusNode;

  /// Shown in the empty search field. UIKit's: "Search".
  final String searchPlaceholder;

  /// Called as the search text changes, and when it is submitted.
  final ValueChanged<String>? onSearchChanged;
  final ValueChanged<String>? onSearchSubmitted;

  /// Draws the glass as UIKit's with Reduce Transparency on: nearly opaque,
  /// heavily blurred, without refraction. Flutter does not report that
  /// setting, so pass it in (for example from a platform channel reading
  /// `UIAccessibility.isReduceTransparencyEnabled`).
  ///
  /// Increase Contrast and Reduce Motion the bar follows by itself, from
  /// [MediaQuery]: with Increase Contrast its glass is filled nearly white,
  /// its tabs drawn in their colors as they are (the selected one's darker,
  /// as UIKit's); with Reduce Motion the selection slides without lifting
  /// into a lens, and nothing swells or flexes.
  final bool reduceTransparency;

  /// The height of the bottom accessory, and its gap above the bar.
  static const double accessoryHeight = 48;
  static const double accessoryGap = 8;

  /// The bar's height with [padding] (UIKit's, 62pt, without), and an
  /// [accessory] above it if there is one.
  static double heightWith(
    EdgeInsetsGeometry? padding, {
    bool accessory = false,
  }) =>
      GlassTabBarPhysics.tabHeight +
      (padding ?? const EdgeInsets.all(GlassTabBarPhysics.inset)).vertical +
      (accessory ? accessoryHeight + accessoryGap : 0);

  GlassTabBarStyle get _style => GlassTabBarStyle(
    selectedColor: selectedColor,
    unselectedColor: unselectedColor,
    badgeColor: badgeColor,
    labelStyle: labelStyle,
  );

  final GlassTabBarDebugView debugView;

  /// Whether the lens reads the same backdrop capture as the bar, taken
  /// before any of the bar's glass. Turn off only to see what the lens would
  /// read otherwise: the bar's rendered glass.
  final bool debugShareBackdrop;

  /// Where [GlassTabBarDebugView.sampling] draws its inspector, in the bar's
  /// coordinates. Defaults to a panel above the bar.
  final Rect? debugInspector;

  /// Holds a press at this point, in the bar's coordinates, from the first
  /// frame on: the lens stays lifted there without a real touch, for still
  /// comparisons.
  final Offset? debugHold;

  /// Draws no tab content, so the glass's optics can be looked at alone.
  final bool debugHideContent;

  /// The optical stages drawn (a [GlassTabBarOptics] mask), to compare them
  /// one at a time.
  final int debugOptics;

  /// Draws the glass's optics at this lift progress (0 to 1) instead of the
  /// lens's, to compare the transition between resting and lifted at fixed
  /// points.
  final double? debugLift;

  static final ShaderProgram _field = ShaderProgram('field.frag');
  static final ShaderProgram _backdrop = ShaderProgram('backdrop.frag');

  /// Loads the bar's shaders ahead of time, so the bar shows from the first
  /// frame. Optional: otherwise it loads them itself, and appears once they
  /// are in.
  static Future<void> precache() =>
      Future.wait(<Future<void>>[_field.load(), _backdrop.load()]);

  @override
  State<GlassTabBar> createState() => _GlassTabBarState();
}

class _GlassTabBarState extends State<GlassTabBar>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final GlassTabBarPhysics _physics = GlassTabBarPhysics(
    count: widget.items.length,
    selectedIndex: _slot(widget.selectedIndex),
  );

  // Tabs are laid out in slots from the left: in a right-to-left
  // Directionality, the first tab takes the last slot. A slot and an index
  // map to each other the same way. (The search tab, index items.length, has
  // no slot: it is a circle of its own.)
  bool _rtl = false;
  int _slot(int index) => _rtl ? widget.items.length - 1 - index : index;

  bool get _searchSelected =>
      widget.search != null && widget.selectedIndex >= widget.items.length;

  final GlassTabBarMinimize _minimize = GlassTabBarMinimize();

  // Whether the bar is opened into its search field, and the field's focus.
  bool get _searchOpen =>
      widget.search != null &&
      widget.searchController != null &&
      _searchSelected;
  FocusNode? _ownFocus;
  FocusNode get _searchFocus =>
      widget.searchFocusNode ?? (_ownFocus ??= FocusNode());

  void _focusChanged() {
    if (mounted) {
      _minimize.setFocus(_searchFocus.hasFocus, _frameTime);
      _wake();
    }
  }

  // Back to the last tab from the search field.
  void _exitSearch() {
    _searchFocus.unfocus();
    widget.onSelected(_slot(_physics.selectedIndex));
  }

  void _closeSearch() {
    widget.searchController?.clear();
    widget.onSearchChanged?.call('');
    _searchFocus.unfocus();
  }

  // Whether the tabs were last built for the dark appearance: their colors
  // resolve for it, and the shader's selected tint goes with them.
  bool _contentDark = false;
  late final Ticker _ticker = createTicker(_tick);
  final _Frame _frame = _Frame();
  int? _pointer;

  // The adaptive appearance, fed by readings of the backdrop under the bar:
  // UIKit reads it about every frame; this, every 50ms while frames are
  // being drawn.
  final GlassAppearance _appearance = GlassAppearance();
  Timer? _sampler;
  bool _sampling = false;
  int _sampledFrame = -1;
  static int _frames = 0;
  static bool _counting = false;

  // The raw vsync time: on the same clock as pointer event time stamps, so
  // touches take effect at the moment they happened.
  static double get _frameTime =>
      SchedulerBinding.instance.currentSystemFrameTimeStamp.inMicroseconds /
      1e6;

  static double _timeOf(PointerEvent event) =>
      event.timeStamp.inMicroseconds / 1e6;

  void _tick(Duration _) {
    final double now = _frameTime;
    if (!(_physics.tick(now) | _appearance.tick(now) | _minimize.tick(now))) {
      _ticker.stop();
    }
    if (_appearance.isDark != _contentDark) {
      setState(() => _contentDark = _appearance.isDark);
    }
    _frame.notify();
  }

  Future<void> _sample() async {
    if (_sampling || !mounted || _frames == _sampledFrame) {
      return;
    }
    final RenderObject? box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) {
      return;
    }
    final GlassBackdropState? backdrop = GlassBackdrop.under(
      MatrixUtils.transformRect(
        box.getTransformTo(null),
        Offset.zero & box.size,
      ),
    );
    if (backdrop == null) {
      return;
    }
    _sampling = true;
    _sampledFrame = _frames;
    try {
      final double? luma = await backdrop.meanLuma(
        GlassAppearance.sampleArea(
          MatrixUtils.transformRect(
            box.getTransformTo(null),
            Offset.zero & box.size,
          ),
        ),
      );
      if (mounted && luma != null) {
        _appearance.sample(luma);
        _wake();
      }
    } finally {
      _sampling = false;
    }
  }

  void _wake() {
    if (!_ticker.isActive) {
      _ticker.start();
    }
  }

  void _handlePointer(PointerEvent event) {
    switch (event) {
      case PointerDownEvent():
        if (_pointer != null) {
          return;
        }
        _pointer = event.pointer;
        _physics.pointerDown(event.localPosition, time: _timeOf(event));
      case PointerMoveEvent():
        if (event.pointer != _pointer) {
          return;
        }
        _physics.pointerMove(event.localPosition, time: _timeOf(event));
      case PointerUpEvent():
        if (event.pointer != _pointer) {
          return;
        }
        _pointer = null;
        final int index = _slot(_physics.pointerUp(time: _timeOf(event)));
        if (index == widget.selectedIndex) {
          widget.onReselected?.call(index);
        } else {
          widget.onSelected(index);
          // If the choice is not taken up, go back to the selected tab.
          SchedulerBinding.instance.addPostFrameCallback((_) {
            final int selected = _slot(widget.selectedIndex);
            if (mounted &&
                !_searchSelected &&
                _pointer == null &&
                _physics.selectedIndex != selected) {
              _physics.select(selected);
              _wake();
            }
          });
        }
      case PointerCancelEvent():
        if (event.pointer != _pointer) {
          return;
        }
        _pointer = null;
        _physics.pointerCancel(time: _timeOf(event));
      default:
        return;
    }
    _wake();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (!_counting) {
      _counting = true;
      SchedulerBinding.instance.addPersistentFrameCallback((_) => _frames++);
    }
    _sampler = Timer.periodic(
      const Duration(milliseconds: 50),
      (_) => _sample(),
    );
    _minimize
      ..set(widget.minimized, 0, animate: false)
      ..setSearch(_searchOpen, 0, animate: false);
    _searchFocus.addListener(_focusChanged);
    GlassTabBar.precache().then((_) {
      if (mounted) {
        _frame.notify();
      }
    });
    final Offset? hold = widget.debugHold;
    if (hold != null) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _physics.pointerDown(hold);
          _wake();
        }
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bool rtl = Directionality.maybeOf(context) == TextDirection.rtl;
    if (rtl != _rtl) {
      _rtl = rtl;
      if (!_searchSelected) {
        _physics.select(_slot(widget.selectedIndex));
      }
    }
    _configureAppearance();
    _wake();
  }

  void _configureAppearance() {
    _appearance
      ..adaptive = widget.adaptive
      ..system = widget.brightness ?? MediaQuery.platformBrightnessOf(context)
      ..contrast = MediaQuery.highContrastOf(context)
      ..reduceTransparency = widget.reduceTransparency;
    // iOS reports Reduce Motion as its own flag, which MediaQuery does not
    // carry.
    _physics.reduceMotion =
        MediaQuery.disableAnimationsOf(context) ||
        View.of(context).platformDispatcher.accessibilityFeatures.reduceMotion;
  }

  @override
  void didChangeAccessibilityFeatures() {
    if (mounted) {
      _configureAppearance();
      _wake();
    }
  }

  @override
  void didUpdateWidget(GlassTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _configureAppearance();
    if (!_searchSelected) {
      final int selected = _slot(widget.selectedIndex);
      if (selected != _physics.selectedIndex) {
        _physics.select(selected);
      }
    }
    if (widget.minimized != oldWidget.minimized) {
      _minimize.set(widget.minimized, _frameTime);
    }
    if (widget.searchFocusNode != oldWidget.searchFocusNode) {
      (oldWidget.searchFocusNode ?? _ownFocus)?.removeListener(_focusChanged);
      _searchFocus.addListener(_focusChanged);
    }
    if (!_searchOpen && _searchFocus.hasFocus) {
      _searchFocus.unfocus();
    }
    _minimize.setSearch(_searchOpen, _frameTime);
    _wake();
  }

  @override
  void dispose() {
    _searchFocus.removeListener(_focusChanged);
    _ownFocus?.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _sampler?.cancel();
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  // The widest label, as UIKit sizes tabs by it: selected, which is widest.
  static double _widestLabel(
    BuildContext context,
    List<GlassTabItem> items,
    GlassTabBarStyle style,
  ) {
    var widest = 0.0;
    final TextStyle label = TabContent.labelStyle(style, selected: true);
    for (final GlassTabItem item in items) {
      final painter = TextPainter(
        text: TextSpan(text: item.label, style: label),
        textDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
      )..layout();
      widest = math.max(widest, painter.width);
      painter.dispose();
    }
    return widest;
  }

  @override
  Widget build(BuildContext context) {
    // The tabs in slot order.
    final List<GlassTabItem> items = <GlassTabItem>[
      for (var slot = 0; slot < widget.items.length; slot++)
        widget.items[_slot(slot)],
    ];
    _contentDark = _appearance.isDark;
    final bool contrast = MediaQuery.highContrastOf(context);
    final Color normal = _contentDark
        ? const Color(0xFFF3F3F3)
        : const Color(0xFF191919);
    // With Increase Contrast, UIKit draws the other tabs in their color as it
    // is rather than through the glass.
    final GlassTabBarStyle style = contrast && widget.unselectedColor == null
        ? GlassTabBarStyle(
            selectedColor: widget.selectedColor,
            unselectedColor: normal,
            badgeColor: widget.badgeColor,
            labelStyle: widget.labelStyle,
          )
        : widget._style;
    Color tintOf(GlassTabItem item) => GlassTabBarStyle.resolve(
      item.selectedColor ?? widget.selectedColor ?? GlassTabBarStyle.systemBlue,
      dark: _contentDark,
      contrast: contrast,
    );
    Widget icon(Widget icon, Color color) => IconTheme.merge(
      data: IconThemeData(color: color, size: 26),
      child: icon,
    );
    final GlassTabItem? search = widget.search;
    // The tab the minimized bar shows: the selected one, or the one last
    // selected while the search tab is.
    final GlassTabItem shown =
        items[_physics.selectedIndex.clamp(0, items.length - 1)];
    Widget layer(GlassTabItem item, TabLayer layer) => widget.debugHideContent
        ? const SizedBox()
        : ExcludeSemantics(
            child: TabContent(
              item: item,
              layer: layer,
              style: style,
              dark: _contentDark,
            ),
          );
    return SizedBox(
      height: GlassTabBar.heightWith(
        widget.padding,
        accessory: widget.accessory != null,
      ),
      child: _TabBarLayout(
        physics: _physics,
        appearance: _appearance,
        frame: _frame,
        onPointer: _handlePointer,
        debugView: widget.debugView,
        shareBackdrop: widget.debugShareBackdrop,
        inspector: widget.debugInspector,
        optics: widget.debugOptics,
        lift: widget.debugLift,
        devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
        contentDark: _contentDark,
        hasOriginal: anyOriginal(items, style),
        labelWidth: _widestLabel(context, items, style),
        tints: <Color>[for (final GlassTabItem item in items) tintOf(item)],
        contrast: contrast,
        glass: (widget.glass ?? const GlassDecoration()).withColor(
          widget.glassColor,
        ),
        indicator: (widget.indicator ?? const GlassDecoration()).withColor(
          widget.indicatorColor,
        ),
        lens: (widget.lens ?? const GlassDecoration()).withColor(
          widget.lensColor,
        ),
        textDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
        padding:
            (widget.padding ?? const EdgeInsets.all(GlassTabBarPhysics.inset))
                .resolve(Directionality.maybeOf(context) ?? TextDirection.ltr),
        tabCount: items.length,
        hasSearch: search != null,
        hasAccessory: widget.accessory != null,
        minimize: _minimize,
        searchSelected: _searchSelected,
        onSearch: () => widget.onSelected(widget.items.length),
        onExpand: widget.onExpand,
        onSearchClose: _closeSearch,
        onSearchExit: _exitSearch,
        onSearchPress: (bool down) {
          _minimize.pressSearch(down, _frameTime);
          _wake();
        },
        hasField: search != null && widget.searchController != null,
        // One child per tab and layer: each layer's tabs in slot order; then
        // the search tab's icon, the minimized bar's icon, and the accessory.
        children: <Widget>[
          for (var slot = 0; slot < items.length; slot++)
            Semantics(
              button: true,
              selected: _slot(slot) == widget.selectedIndex,
              label: items[slot].label,
              value: items[slot].badge,
              onTap: () => widget.onSelected(_slot(slot)),
              child: layer(items[slot], TabLayer.values[0]),
            ),
          for (final TabLayer l in TabLayer.values.skip(1))
            for (final GlassTabItem item in items) layer(item, l),
          if (search != null)
            Semantics(
              button: true,
              selected: _searchSelected,
              label: search.label,
              onTap: () => widget.onSelected(widget.items.length),
              // Selected, it takes the tint; opened into its field, it is
              // the field's magnifying glass, in the label's color.
              child: _searchSelected && !_searchOpen
                  ? icon(search.selectedIcon ?? search.icon, tintOf(search))
                  : icon(search.icon, search.unselectedColor ?? normal),
            ),
          Semantics(
            button: true,
            label: shown.label,
            onTap: _searchOpen ? _exitSearch : widget.onExpand,
            // While searching, it is the last tab, not the selected one.
            child: _searchOpen
                ? icon(shown.icon, normal)
                : icon(shown.selectedIcon ?? shown.icon, tintOf(shown)),
          ),
          if (widget.accessory case final Widget accessory)
            DefaultTextStyle.merge(
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: _contentDark
                    ? const Color(0xFFFFFFFF)
                    : const Color(0xFF000000),
              ),
              child: IconTheme.merge(
                data: IconThemeData(
                  color: _contentDark
                      ? const Color(0xFFFFFFFF)
                      : const Color(0xFF000000),
                  size: 20,
                ),
                child: accessory,
              ),
            ),
          if (search != null && widget.searchController != null) ...<Widget>[
            // Only while open, for screen readers and focus.
            ExcludeSemantics(
              excluding: !_searchOpen,
              child: ExcludeFocus(
                excluding: !_searchOpen,
                child: _SearchField(
                  controller: widget.searchController!,
                  focusNode: _searchFocus,
                  placeholder: widget.searchPlaceholder,
                  dark: _contentDark,
                  cursorColor: tintOf(search),
                  onChanged: widget.onSearchChanged,
                  onSubmitted: widget.onSearchSubmitted,
                ),
              ),
            ),
            ExcludeSemantics(
              excluding: !_searchOpen,
              child: Semantics(
                button: true,
                label: 'Close',
                onTap: _closeSearch,
                child: icon(
                  const BarGlyph.close(),
                  _contentDark
                      ? const Color(0xFFFFFFFF)
                      : const Color(0xFF000000),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The search field's content: UIKit's magnifying glass 13pt from its
/// leading end, and the text 41.7pt from it, 17pt.
class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.placeholder,
    required this.dark,
    required this.cursorColor,
    this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String placeholder;
  final bool dark;
  final Color cursorColor;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    // UIKit's label color, and its placeholder's: the secondary label's
    // color at about 76% over the glass (as its vibrancy comes out).
    final Color text = dark ? const Color(0xFFFFFFFF) : const Color(0xFF000000);
    final Color secondary = dark
        ? const Color(0xC2EBEBF5)
        : const Color(0xC23C3C43);
    return Row(
      children: <Widget>[
        const SizedBox(width: 13),
        SizedBox(
          width: 20.67,
          child: Align(
            // The search tab's own icon slides here (see _paintExtras).
            child: const SizedBox(),
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
            cursorColor: cursorColor,
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

class _Frame extends ChangeNotifier {
  void notify() => notifyListeners();
}

class _TabBarLayout extends MultiChildRenderObjectWidget {
  const _TabBarLayout({
    required this.physics,
    required this.appearance,
    required this.frame,
    required this.onPointer,
    required this.debugView,
    required this.shareBackdrop,
    required this.inspector,
    required this.optics,
    required this.lift,
    required this.devicePixelRatio,
    required this.contentDark,
    required this.hasOriginal,
    required this.labelWidth,
    required this.tints,
    required this.glass,
    required this.indicator,
    required this.lens,
    required this.textDirection,
    required this.padding,
    required this.tabCount,
    required this.hasSearch,
    required this.hasAccessory,
    required this.minimize,
    required this.searchSelected,
    required this.onSearch,
    required this.onExpand,
    required this.onSearchClose,
    required this.onSearchExit,
    required this.onSearchPress,
    required this.hasField,
    required this.contrast,
    required super.children,
  });

  final VoidCallback onSearchClose;
  final VoidCallback onSearchExit;
  final ValueChanged<bool> onSearchPress;
  final bool hasField;
  final bool contrast;
  final int tabCount;
  final bool hasSearch;
  final bool hasAccessory;
  final GlassTabBarMinimize minimize;
  final bool searchSelected;
  final VoidCallback onSearch;
  final VoidCallback? onExpand;

  final GlassTabBarPhysics physics;
  final GlassAppearance appearance;
  final Listenable frame;
  final ValueChanged<PointerEvent> onPointer;
  final GlassTabBarDebugView debugView;
  final bool shareBackdrop;
  final Rect? inspector;
  final int optics;
  final double? lift;
  final double devicePixelRatio;
  final bool contentDark;
  final bool hasOriginal;
  final double labelWidth;
  final List<Color> tints;
  final GlassDecoration glass;
  final GlassDecoration indicator;
  final GlassDecoration lens;
  final TextDirection textDirection;
  final EdgeInsets padding;

  @override
  RenderGlassTabBar createRenderObject(BuildContext context) {
    return RenderGlassTabBar(
      physics: physics,
      appearance: appearance,
      frame: frame,
      onPointer: onPointer,
      debugView: debugView,
      shareBackdrop: shareBackdrop,
      inspector: inspector,
      optics: optics,
      lift: lift,
      devicePixelRatio: devicePixelRatio,
      contentDark: contentDark,
      hasOriginal: hasOriginal,
      labelWidth: labelWidth,
      tints: tints,
      glass: glass,
      indicator: indicator,
      lens: lens,
      textDirection: textDirection,
      padding: padding,
      tabCount: tabCount,
      hasSearch: hasSearch,
      hasAccessory: hasAccessory,
      minimize: minimize,
      searchSelected: searchSelected,
      onSearch: onSearch,
      onExpand: onExpand,
      onSearchClose: onSearchClose,
      onSearchExit: onSearchExit,
      onSearchPress: onSearchPress,
      hasField: hasField,
      contrast: contrast,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderGlassTabBar renderObject,
  ) {
    renderObject
      ..onPointer = onPointer
      ..debugView = debugView
      ..shareBackdrop = shareBackdrop
      ..inspector = inspector
      ..optics = optics
      ..lift = lift
      ..devicePixelRatio = devicePixelRatio
      ..contentDark = contentDark
      ..hasOriginal = hasOriginal
      ..labelWidth = labelWidth
      ..tints = tints
      ..glass = glass
      ..indicator = indicator
      ..lens = lens
      ..textDirection = textDirection
      ..padding = padding
      ..tabCount = tabCount
      ..hasSearch = hasSearch
      ..hasAccessory = hasAccessory
      ..searchSelected = searchSelected
      ..onSearch = onSearch
      ..onExpand = onExpand
      ..onSearchClose = onSearchClose
      ..onSearchExit = onSearchExit
      ..onSearchPress = onSearchPress
      ..hasField = hasField
      ..contrast = contrast;
  }
}

class _TabParentData extends ContainerBoxParentData<RenderBox> {}

/// Lays out a [GlassTabBar]'s tabs (each four times: a child for each
/// [TabLayer]), takes its touches, and paints the glass and the tabs where
/// [GlassTabBarPhysics] puts them.
///
/// The glass is two passes over one backdrop capture. The bar's pass comes
/// first and takes the capture: everything behind the bar, before any of its
/// glass. The lens's pass comes after the tabs and reads that same capture
/// (a shared [BackdropKey]), so it can reach content far outside itself but
/// never sees the bar's glass, the tabs, or itself. The tabs under the lens
/// are not painted here but lifted into it: the lens's shader draws them
/// from an atlas of the tabs in the selected style, grown and lensed.
class RenderGlassTabBar extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _TabParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _TabParentData> {
  RenderGlassTabBar({
    required this._physics,
    required this._appearance,
    required this._frame,
    required this.onPointer,
    required this._debugView,
    required this._shareBackdrop,
    required this._inspector,
    this._optics = GlassTabBarOptics.all,
    this._lift,
    required this._devicePixelRatio,
    this._contentDark = false,
    this._hasOriginal = false,
    this._labelWidth = 0,
    this._tints = const <Color>[],
    this._glass = const GlassDecoration(),
    this._indicator = const GlassDecoration(),
    this._lens = const GlassDecoration(),
    this._textDirection = TextDirection.ltr,
    this._padding = const EdgeInsets.all(GlassTabBarPhysics.inset),
    int tabCount = 0,
    this._hasSearch = false,
    this._hasAccessory = false,
    GlassTabBarMinimize? minimize,
    this._searchSelected = false,
    this.onSearch,
    this.onExpand,
    this.onSearchClose,
    this.onSearchExit,
    this.onSearchPress,
    this._contrast = false,
    this._hasField = false,
  }) : _count = tabCount,
       _minimize = minimize ?? GlassTabBarMinimize();

  final GlassTabBarMinimize _minimize;

  /// Called when the search tab's circle is tapped.
  VoidCallback? onSearch;

  /// Called when the minimized bar is tapped.
  VoidCallback? onExpand;

  /// Called as the finger comes down on the search circle, and up.
  ValueChanged<bool>? onSearchPress;

  /// Called when the search field's close button is tapped, and when the
  /// collapsed platter is tapped while the field is open (back to the tabs).
  VoidCallback? onSearchClose;
  VoidCallback? onSearchExit;

  /// Whether the search tab opens into a search field (children for its
  /// content and its close button follow the accessory).
  bool get hasField => _hasField;
  bool _hasField;
  set hasField(bool value) {
    if (value != _hasField) {
      _hasField = value;
      markNeedsLayout();
    }
  }

  /// How many tabs the platter holds (each a child per [TabLayer]; any
  /// children after them are the search tab's icon, the minimized bar's
  /// icon and the accessory).
  int get tabCount => _count;
  int _count;
  set tabCount(int value) {
    if (value != _count) {
      _count = value;
      markNeedsLayout();
    }
  }

  bool get hasSearch => _hasSearch;
  bool _hasSearch;
  set hasSearch(bool value) {
    if (value != _hasSearch) {
      _hasSearch = value;
      markNeedsLayout();
    }
  }

  bool get hasAccessory => _hasAccessory;
  bool _hasAccessory;
  set hasAccessory(bool value) {
    if (value != _hasAccessory) {
      _hasAccessory = value;
      markNeedsLayout();
    }
  }

  /// Increase Contrast: the selected tabs drawn in their color as it is.
  bool get contrast => _contrast;
  bool _contrast;
  set contrast(bool value) {
    if (value != _contrast) {
      _contrast = value;
      markNeedsPaint();
    }
  }

  /// Whether the search tab is the selected one: the platter then shows no
  /// selection at rest.
  bool get searchSelected => _searchSelected;
  bool _searchSelected;
  set searchSelected(bool value) {
    if (value != _searchSelected) {
      _searchSelected = value;
      markNeedsPaint();
    }
  }

  final GlassTabBarPhysics _physics;
  final GlassAppearance _appearance;
  final Listenable _frame;
  ValueChanged<PointerEvent> onPointer;

  GlassTabBarDebugView get debugView => _debugView;
  GlassTabBarDebugView _debugView;
  set debugView(GlassTabBarDebugView value) {
    if (value != _debugView) {
      _debugView = value;
      markNeedsCompositingBitsUpdate();
      markNeedsPaint();
    }
  }

  bool get shareBackdrop => _shareBackdrop;
  bool _shareBackdrop;
  set shareBackdrop(bool value) {
    if (value != _shareBackdrop) {
      _shareBackdrop = value;
      markNeedsPaint();
    }
  }

  Rect? get inspector => _inspector;
  Rect? _inspector;
  set inspector(Rect? value) {
    if (value != _inspector) {
      _inspector = value;
      markNeedsPaint();
    }
  }

  /// The optical stages drawn: a [GlassTabBarOptics] mask.
  int get optics => _optics;
  int _optics;
  set optics(int value) {
    if (value != _optics) {
      _optics = value;
      markNeedsPaint();
    }
  }

  /// The lift progress the optics are drawn at, when not the lens's own.
  double? get lift => _lift;
  double? _lift;
  set lift(double? value) {
    if (value != _lift) {
      _lift = value;
      markNeedsPaint();
    }
  }

  double get devicePixelRatio => _devicePixelRatio;
  double _devicePixelRatio;
  set devicePixelRatio(double value) {
    if (value != _devicePixelRatio) {
      _devicePixelRatio = value;
      markNeedsPaint();
    }
  }

  /// Whether the tabs are drawn for the dark appearance: the selected tint
  /// is mixed in as UIKit's dark matrix does.
  bool get contentDark => _contentDark;
  bool _contentDark;
  set contentDark(bool value) {
    if (value != _contentDark) {
      _contentDark = value;
      markNeedsPaint();
    }
  }

  /// Whether any tab has content drawn as it is (badges, original-color
  /// icons, a set unselected color): the shader reads it only then.
  bool get hasOriginal => _hasOriginal;
  bool _hasOriginal;
  set hasOriginal(bool value) {
    if (value != _hasOriginal) {
      _hasOriginal = value;
      markNeedsPaint();
    }
  }

  /// The widest label's width, which sizes a bar of up to three tabs.
  double get labelWidth => _labelWidth;
  double _labelWidth;
  set labelWidth(double value) {
    if (value != _labelWidth) {
      _labelWidth = value;
      markNeedsLayout();
    }
  }

  /// Each tab's selected color (in slot order), resolved for the appearance:
  /// the shader reads it from a strip under the content atlas, so a
  /// template's own colors never matter, as in UIKit.
  List<Color> get tints => _tints;
  List<Color> _tints;
  set tints(List<Color> value) {
    if (!listEquals(value, _tints)) {
      _tints = value;
      markNeedsPaint();
    }
  }

  /// The decorations of the platter, the resting selection and the lens
  /// (see [GlassTabBar.glass]).
  GlassDecoration get glass => _glass;
  GlassDecoration _glass;
  set glass(GlassDecoration value) {
    if (value != _glass) {
      _glass = value;
      markNeedsPaint();
    }
  }

  GlassDecoration get indicator => _indicator;
  GlassDecoration _indicator;
  set indicator(GlassDecoration value) {
    if (value != _indicator) {
      _indicator = value;
      markNeedsPaint();
    }
  }

  GlassDecoration get lens => _lens;
  GlassDecoration _lens;
  set lens(GlassDecoration value) {
    if (value != _lens) {
      _lens = value;
      markNeedsPaint();
    }
  }

  /// Space inside the bar around its tabs (see [GlassTabBar.padding]).
  EdgeInsets get padding => _padding;
  EdgeInsets _padding;
  set padding(EdgeInsets value) {
    if (value != _padding) {
      _padding = value;
      markNeedsLayout();
    }
  }

  // Each tab's content is laid out in a box of UIKit's 62pt bar, its pill
  // 4pt in from its top and bottom; the padding moves it down by this much.
  static const double _rowHeight =
      GlassTabBarPhysics.tabHeight + 2 * GlassTabBarPhysics.inset;
  double get _rowTop => _padding.top - GlassTabBarPhysics.inset;

  /// For gradients' directional alignments.
  TextDirection get textDirection => _textDirection;
  TextDirection _textDirection;
  set textDirection(TextDirection value) {
    if (value != _textDirection) {
      _textDirection = value;
      markNeedsPaint();
    }
  }

  GlassTint _tint(Color? color, GlassFill fill) {
    final Color? resolved = color == null
        ? null
        : GlassTabBarStyle.resolve(color, dark: _contentDark);
    return fill == GlassFill.paint
        ? GlassTint.paint(resolved)
        : GlassTint(resolved, darkAppearance: _contentDark);
  }

  // A decoration's tint over [shape] (capture pixels): at its gradient's
  // start and end, the gradient's axis, and whether it is painted rather
  // than tinted; a color is both ends at once.
  (GlassTint, GlassTint, Offset, Offset, bool) _decorationTint(
    GlassDecoration decoration,
    Rect shape,
  ) {
    final GlassFill fill = decoration.fill;
    final bool paint = fill == GlassFill.paint;
    final LinearGradient? gradient = decoration.gradient;
    if (gradient == null || gradient.colors.isEmpty) {
      final GlassTint t = _tint(decoration.color, fill);
      return (t, t, Offset.zero, Offset.zero, paint);
    }
    return (
      _tint(gradient.colors.first, fill),
      _tint(gradient.colors.last, fill),
      gradient.begin.resolve(_textDirection).withinRect(shape),
      gradient.end.resolve(_textDirection).withinRect(shape),
      paint,
    );
  }

  ui.FragmentShader? _fieldShader;

  // One shader per pass: a shader image filter reads its uniforms only when
  // it is composited, after all passes have been painted.
  final List<_BackdropUniforms> _passes = <_BackdropUniforms>[];

  // One capture for the bar and the lens (and the inspector); a second key
  // only for the comparison where the lens reads the bar's glass.
  final BackdropKey _sharedCapture = BackdropKey();
  final BackdropKey _lensOwnCapture = BackdropKey();

  final LayerHandle<ClipRectLayer> _barClip = LayerHandle<ClipRectLayer>();
  final LayerHandle<BackdropFilterLayer> _barPass =
      LayerHandle<BackdropFilterLayer>();
  final LayerHandle<ClipRectLayer> _lensClip = LayerHandle<ClipRectLayer>();
  final LayerHandle<BackdropFilterLayer> _lensPass =
      LayerHandle<BackdropFilterLayer>();
  final LayerHandle<ClipRectLayer> _inspectorClip =
      LayerHandle<ClipRectLayer>();
  final LayerHandle<BackdropFilterLayer> _inspectorPass =
      LayerHandle<BackdropFilterLayer>();

  // The platter's frost, drawn into the backdrop before the passes capture
  // it: two blurs of one capture of its own.
  final BackdropKey _frostCapture = BackdropKey();
  final LayerHandle<ClipPathLayer> _frostClip = LayerHandle<ClipPathLayer>();
  final LayerHandle<BackdropFilterLayer> _frostHeavy =
      LayerHandle<BackdropFilterLayer>();
  final LayerHandle<BackdropFilterLayer> _frostLight =
      LayerHandle<BackdropFilterLayer>();

  bool get _drawsGlass =>
      (_debugView == GlassTabBarDebugView.none ||
          _debugView == GlassTabBarDebugView.sampling) &&
      ui.ImageFilter.isShaderFilterSupported;

  @override
  bool get alwaysNeedsCompositing => _drawsGlass;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _TabParentData) {
      child.parentData = _TabParentData();
    }
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _frame.addListener(_onFrame);
  }

  @override
  void detach() {
    _frame.removeListener(_onFrame);
    super.detach();
  }

  // A new animation frame repaints the glass, not the tabs' content.
  bool _repaintingFrame = false;
  void _onFrame() {
    _repaintingFrame = true;
    markNeedsPaint();
    _repaintingFrame = false;
  }

  @override
  void markNeedsPaint() {
    // Anything else (a tab's content changing, a new layout, a setting) may
    // change what the lens shows of the tabs.
    if (!_repaintingFrame) {
      _contentDirty = true;
    }
    super.markNeedsPaint();
  }

  @override
  void dispose() {
    _contentAtlas?.dispose();
    _noContent?.dispose();
    _fieldShader?.dispose();
    for (final _BackdropUniforms u in _passes) {
      u.shader.dispose();
    }
    _clearGlassLayers();
    super.dispose();
  }

  void _clearGlassLayers() {
    _clearFrost();
    _barClip.layer = null;
    _barPass.layer = null;
    _lensClip.layer = null;
    _lensPass.layer = null;
    _inspectorClip.layer = null;
    _inspectorPass.layer = null;
    _glowClip.layer = null;
  }

  int get _tabCount => _count;

  // The child at [index], or null.
  RenderBox? _childAt(int index) {
    RenderBox? child = firstChild;
    for (var i = 0; i < index && child != null; i++) {
      child = childAfter(child);
    }
    return child;
  }

  int get _extrasStart => _count * tabLayerCount;
  int get _searchIconIndex => _extrasStart;
  int get _minimizedIconIndex => _extrasStart + (_hasSearch ? 1 : 0);
  int get _accessoryIndex => _minimizedIconIndex + 1;
  int get _fieldIndex => _accessoryIndex + (_hasAccessory ? 1 : 0);
  RenderBox? get _searchIcon => _hasSearch ? _childAt(_searchIconIndex) : null;
  RenderBox? get _minimizedIcon => _childAt(_minimizedIconIndex);
  RenderBox? get _accessory => _hasAccessory ? _childAt(_accessoryIndex) : null;
  RenderBox? get _searchField => _hasField ? _childAt(_fieldIndex) : null;
  RenderBox? get _closeIcon => _hasField ? _childAt(_fieldIndex + 1) : null;

  // The tab row's top in the bar: under the accessory, if there is one.
  double get _barRowTop => _hasAccessory
      ? GlassTabBar.accessoryHeight + GlassTabBar.accessoryGap
      : 0;
  double get _barRowHeight => GlassTabBarPhysics.tabHeight + _padding.vertical;

  // Where the physics' origin (the platter's top left at rest) sits in the
  // bar, and the search tab's circle.
  Offset _platterOrigin = Offset.zero;
  Rect _searchCircle = Rect.zero;

  // UIKit's minimized bar: 48pt circles, 7pt in from the row's ends (in its
  // 62pt circles' place), the accessory between them 8pt from each. Its
  // search field: from 12pt after the circle to the row's end, and with the
  // keyboard, 12pt short of a close button there.
  static const double _minimizedSize = 48;
  static const double _minimizedGap = 8;
  static const double _fieldGap = 12;

  // The search field's layout while it has the keyboard (its content is laid
  // out once, at this width).
  Rect _fieldFocused = Rect.zero;

  /// The glass shapes as drawn now, in the bar's coordinates: the platter
  /// and its selection (collapsing into [circle] as the bar minimizes or
  /// searches), the search tab's circle (growing into its field), the
  /// accessory and the field's close button (each empty when there is none).
  ({
    Rect platter,
    Rect lens,
    Rect search,
    Rect accessory,
    Rect close,
    Rect circle,
    Rect searchCircle,
    Rect field,
  })
  _shapes() {
    final double row = _barRowHeight;
    final double mid = _barRowTop + row / 2;
    const double d = _minimizedSize;
    final double inset = (GlassTabBar.height - d) / 2;
    final bool rtl = _textDirection == TextDirection.rtl;
    Rect mirror(Rect r) => rtl
        ? Rect.fromLTRB(
            size.width - r.right,
            r.top,
            size.width - r.left,
            r.bottom,
          )
        : r;
    final Rect circle = mirror(Rect.fromLTWH(inset, mid - d / 2, d, d));
    final Rect searchMin = mirror(
      Rect.fromLTWH(size.width - inset - d, mid - d / 2, d, d),
    );
    final GlassTabBarMinimize m = _minimize;
    Rect toward(Rect from, double c, double w, double h) => Rect.fromCenter(
      center: Offset.lerp(from.center, circle.center, c)!,
      width: ui.lerpDouble(from.width, d, w)!,
      height: ui.lerpDouble(from.height, d, h)!,
    );
    var accessory = Rect.zero;
    if (_hasAccessory) {
      final double to = _hasSearch
          ? size.width - inset - d - _minimizedGap
          : size.width - inset;
      final Rect inline = mirror(
        Rect.fromLTRB(inset + d + _minimizedGap, mid - d / 2, to, mid + d / 2),
      );
      final Rect above = Rect.fromLTWH(
        0,
        0,
        size.width,
        GlassTabBar.accessoryHeight,
      );
      final double span = m.accessorySpan.value;
      final double drop = m.accessoryDrop.value;
      final double l = ui.lerpDouble(above.left, inline.left, span)!;
      final double r = ui.lerpDouble(above.right, inline.right, span)!;
      final double t = ui.lerpDouble(above.top, inline.top, drop)!;
      accessory = Rect.fromLTRB(l, t, r, t + GlassTabBar.accessoryHeight);
    }
    var search = Rect.zero, close = Rect.zero, searchCircle = Rect.zero;
    var fieldRect = Rect.zero;
    if (_hasSearch) {
      // The circle shrinks with the bar minimizing, and swells pressed.
      final Rect resting = Rect.lerp(_searchCircle, searchMin, m.size.value)!;
      searchCircle = Rect.fromCenter(
        center: resting.center,
        width: resting.width * m.searchPress.value,
        height: resting.height * m.searchPress.value,
      );
      search = searchCircle;
      if (_hasField) {
        final double left = inset + d + _fieldGap;
        final Rect open = mirror(
          Rect.fromLTRB(left, mid - d / 2, size.width - inset, mid + d / 2),
        );
        final Rect focused = mirror(
          Rect.fromLTRB(
            left,
            mid - d / 2,
            size.width - inset - d - _fieldGap,
            mid + d / 2,
          ),
        );
        _fieldFocused = focused;
        final Rect field = Rect.lerp(open, focused, m.focus.value)!;
        fieldRect = field;
        search = Rect.lerp(searchCircle, field, m.searchOpen.value)!;
        final double f = m.focus.value.clamp(0.0, 1.5);
        close = Rect.fromCenter(
          center: searchMin.center,
          width: d * f,
          height: d * f,
        );
      }
    }
    return (
      platter: toward(
        _physics.platterRect.shift(_platterOrigin),
        m.platterCenter.value,
        m.platterWidth.value,
        m.platterHeight.value,
      ),
      lens: toward(
        _physics.lensRect.shift(_platterOrigin),
        m.center.value,
        m.size.value,
        m.size.value,
      ),
      search: search,
      accessory: accessory,
      close: close,
      circle: circle,
      searchCircle: searchCircle,
      field: fieldRect,
    );
  }

  @override
  void performLayout() {
    _contentDirty = true;
    final int count = _tabCount;
    final double row = _barRowHeight;
    final double top = _barRowTop;
    final double? natural = GlassTabBarPhysics.naturalWidth(
      count,
      _labelWidth,
      horizontal: _padding.horizontal,
      search: _hasSearch,
    );
    final double full = constraints.hasBoundedWidth
        ? constraints.maxWidth
        : 398;
    // A bar with a search tab or an accessory spans its width; one of up
    // to three tabs alone hugs them.
    final bool spans = natural == null || _hasSearch || _hasAccessory;
    size = constraints.constrain(Size(spans ? full : natural, top + row));
    final double platterWidth = _hasSearch
        ? natural ?? math.max(size.width - row - _minimizedGap, 0)
        : natural ?? size.width;
    final bool rtl = _textDirection == TextDirection.rtl;
    final double x = _hasSearch
        ? (rtl ? size.width - platterWidth : 0)
        : (size.width - platterWidth) / 2;
    _platterOrigin = Offset(x, top);
    _searchCircle = Rect.fromLTWH(rtl ? 0 : size.width - row, top, row, row);
    if (count == 0) {
      return;
    }
    _physics.layout(
      Size(platterWidth, row),
      count,
      padding: _padding,
      search: _hasSearch,
    );
    final double width = _physics.pillWidth;
    final tight = BoxConstraints.tight(Size(width, _rowHeight));
    var i = 0;
    RenderBox? child = firstChild;
    while (child != null && i < _extrasStart) {
      child.layout(tight);
      (child.parentData! as _TabParentData).offset = Offset(
        _physics.tabCenter(i % count) - width / 2,
        _rowTop,
      );
      child = childAfter(child);
      i++;
    }
    // The icons, the accessory and the field sit where the glass is drawn
    // each frame.
    _searchIcon?.layout(
      BoxConstraints.loose(Size.square(row)),
      parentUsesSize: true,
    );
    _minimizedIcon?.layout(
      BoxConstraints.loose(const Size.square(_minimizedSize)),
      parentUsesSize: true,
    );
    final double inline =
        size.width -
        2 * ((GlassTabBar.height - _minimizedSize) / 2) -
        (_minimizedSize + _minimizedGap) * (_hasSearch ? 2 : 1);
    _accessory?.layout(
      BoxConstraints(
        maxWidth: math.max(math.min(size.width, inline) - 32, 0),
        maxHeight: GlassTabBar.accessoryHeight,
      ),
      parentUsesSize: true,
    );
    final shapes = _shapes();
    _searchField?.layout(BoxConstraints.tight(_fieldFocused.size));
    _closeIcon?.layout(
      BoxConstraints.loose(const Size.square(_minimizedSize)),
      parentUsesSize: true,
    );
    // Where they sit at rest (they are painted where the glass is drawn,
    // which these follow while it moves): for hit testing and semantics.
    void place(RenderBox? child, Rect rect) {
      if (child != null) {
        (child.parentData! as _TabParentData).offset =
            rect.center - child.size.center(Offset.zero);
      }
    }

    place(_searchIcon, shapes.search);
    place(_minimizedIcon, shapes.circle);
    place(_accessory, shapes.accessory);
    place(_closeIcon, shapes.close);
    if (_searchField case final RenderBox field) {
      (field.parentData! as _TabParentData).offset = _fieldOrigin(shapes);
    }
  }

  // Where the field's content sits: at the field's leading end.
  Offset _fieldOrigin(
    ({
      Rect platter,
      Rect lens,
      Rect search,
      Rect accessory,
      Rect close,
      Rect circle,
      Rect searchCircle,
      Rect field,
    })
    shapes,
  ) {
    final bool rtl = _textDirection == TextDirection.rtl;
    final Rect f = shapes.search;
    return Offset(
      rtl ? f.right - _fieldFocused.width : f.left,
      f.center.dy - _fieldFocused.height / 2,
    );
  }

  @override
  bool hitTestSelf(Offset position) => _glassAt(position) != null;

  // The glass at [position]: 0 the platter (while expanded, its whole row),
  // 1 the search circle or field, 2 the accessory, 3 the field's close
  // button; null for none.
  int? _glassAt(Offset position) {
    final shapes = _shapes();
    bool inside(Rect r) =>
        !r.isEmpty &&
        RRect.fromRectAndRadius(
          r,
          Radius.circular(r.shortestSide / 2),
        ).contains(position);
    if (_hasAccessory && inside(shapes.accessory)) {
      return 2;
    }
    if (_hasField && _minimize.searching && inside(shapes.close)) {
      return 3;
    }
    if (_hasSearch && inside(shapes.search)) {
      return 1;
    }
    final bool platter = _minimize.collapsed
        ? inside(shapes.platter)
        : (_platterOrigin & _physics.size).contains(position);
    return platter ? 0 : null;
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final int? glass = _glassAt(position);
    final shapes = _shapes();
    RenderBox? child;
    Offset at = Offset.zero;
    if (glass == 2 && _accessory != null) {
      child = _accessory;
      at = shapes.accessory.center - child!.size.center(Offset.zero);
    } else if (glass == 1 && _minimize.searching && _searchField != null) {
      child = _searchField;
      at = _fieldOrigin(shapes);
    }
    if (child == null) {
      return false;
    }
    final RenderBox target = child;
    return result.addWithPaintOffset(
      offset: at,
      position: position,
      hitTest: (BoxHitTestResult result, Offset transformed) =>
          target.hitTest(result, position: transformed),
    );
  }

  // The pointer whose events go to the platter's physics, and one tapping
  // the search circle, the field's close button or the collapsed platter.
  int? _forwarded;
  int? _tapped;
  int? _tappedGlass;

  @override
  void handleEvent(PointerEvent event, BoxHitTestEntry entry) {
    if (event is PointerDownEvent) {
      final int? glass = _glassAt(event.localPosition);
      if (glass == 0 && !_minimize.collapsed) {
        _forwarded = event.pointer;
      } else if (glass == 0 ||
          glass == 3 ||
          (glass == 1 && !_minimize.searching)) {
        _tapped = event.pointer;
        _tappedGlass = glass;
        if (glass == 1) {
          onSearchPress?.call(true);
        }
        return;
      } else {
        return;
      }
    }
    if (event.pointer == _forwarded) {
      // In the physics' coordinates, from the platter's origin.
      onPointer(
        event.transformed(
          Matrix4.translationValues(-_platterOrigin.dx, -_platterOrigin.dy, 0)
            ..multiply(event.transform ?? Matrix4.identity()),
        ),
      );
      if (event is PointerUpEvent || event is PointerCancelEvent) {
        _forwarded = null;
      }
    } else if (event.pointer == _tapped) {
      if (event is PointerUpEvent &&
          _glassAt(event.localPosition) == _tappedGlass) {
        switch (_tappedGlass) {
          case 1:
            onSearch?.call();
          case 3:
            onSearchClose?.call();
          default:
            // The collapsed platter: back to the tabs.
            (_minimize.searching ? onSearchExit : onExpand)?.call();
        }
      }
      if (event is PointerUpEvent || event is PointerCancelEvent) {
        if (_tappedGlass == 1) {
          onSearchPress?.call(false);
        }
        _tapped = null;
      }
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_tabCount == 0) {
      return;
    }
    final ui.FragmentProgram? program = GlassTabBar._backdrop.program;
    if (_drawsGlass && program == null) {
      // The shaders are loading (GlassTabBar.precache): nothing for a frame
      // or two, rather than the flat fallback.
      _clearGlassLayers();
      return;
    }
    if (!_drawsGlass || program == null) {
      _clearGlassLayers();
      _paintField(context.canvas, offset + _platterOrigin);
      context.pushTransform(
        needsCompositing,
        offset + _platterOrigin,
        _physics.platterTransform,
        _paintTabs,
      );
      return;
    }
    _paintGlass(context, offset, program);
  }

  // --------------------------------------------------------------- the glass

  void _paintGlass(
    PaintingContext context,
    Offset offset,
    ui.FragmentProgram program,
  ) {
    final bool diagnostic = _debugView == GlassTabBarDebugView.sampling;
    while (_passes.length < 4) {
      _passes.add(_BackdropUniforms(program.fragmentShader()));
    }
    final _CaptureSpace space = _CaptureSpace(
      getTransformTo(null),
      _devicePixelRatio,
    );
    final shapes = _shapes();
    final Rect platter = shapes.platter;
    final Rect lens = shapes.lens;
    final Offset? touch = _physics.touch == null
        ? null
        : _physics.touch! + _platterOrigin;

    // How much the tabs and the selection show: the tabs fade (and blur) as
    // the bar collapses, and the selection with them; while the search tab
    // is selected, the selection shows only lifted (pressed).
    final double collapsed = _minimize.fade.value.clamp(0.0, 1.0);
    final double contentAlpha = 1 - collapsed;
    final double selectionAlpha =
        (_searchSelected ? (_lift ?? _physics.liftProgress) : 1.0) *
        contentAlpha;

    // The same geometry for every pass, in capture pixels.
    final Rect platterPixels = space.rect(platter);
    final Rect lensPixels = space.rect(lens);
    final Rect searchPixels = _hasSearch
        ? space.rect(shapes.search)
        : Rect.zero;
    final Rect accessoryPixels = _hasAccessory
        ? space.rect(shapes.accessory)
        : Rect.zero;
    final Rect closePixels = shapes.close.isEmpty
        ? Rect.zero
        : space.rect(shapes.close);
    final Offset finger = touch == null ? Offset.zero : space.point(touch);
    final Rect inspector = _inspectorRect;
    final Rect inspectorPixels = space.rect(inspector);
    final Rect window = space.rect(
      Rect.fromCenter(
        center: lens.center,
        width: inspector.width / _inspectorZoom,
        height: inspector.height / _inspectorZoom,
      ),
    );

    // The glass's optics are in its own points: the lens is drawn scaled by
    // the platter and by its flex, the platter by its swell and stretch.
    final double platterScale = math.sqrt(
      _physics.platterScaleX * _physics.platterScaleY,
    );
    final Size flex = _physics.flexScale;
    final double lensScale = platterScale * math.sqrt(flex.width * flex.height);

    // The tabs in the selected style, which the lens draws itself.
    final ui.Image atlas = _ensureContentAtlas();
    // The tabs' content is laid out in the physics' coordinates. As the
    // platter collapses it stays in place, fading and blurring, and the
    // platter's shape clips it, as UIKit's does.
    final Offset barOrigin = space.point(_platterOrigin);
    final Offset platterCenter = _physics.size.center(Offset.zero);
    final Offset drift = _physics.platterDrift;
    final Size squeeze = Size(_physics.platterScaleX, _physics.platterScaleY);
    final int count = _tabCount;

    // The fingertip glow, for the lens's view of it: a gaussian of the
    // blurred disk's peak and volume.
    final Offset? glowCenter = _physics.glowCenter;
    final double glowAlpha = _optics & GlassTabBarOptics.press != 0
        ? _physics.glowAlpha
        : 0;
    final double glowRadius = space.pointSize * _physics.glowSize / 2;
    final double glowSigma = space.pointSize * _physics.glowSigma;
    final double glowPeak =
        1 - math.exp(-glowRadius * glowRadius / (2 * glowSigma * glowSigma));
    final double glowVariance = glowRadius * glowRadius / (2 * glowPeak);
    final Offset glowPixels = glowCenter == null
        ? Offset.zero
        : space.point(glowCenter + _platterOrigin);

    // The appearance's color inputs.
    final GlassAppearance appearance = _appearance;
    final (double, double, double, double) face = appearance.face;
    final double shadow = appearance.shadow;
    final (double, double, double) platterRim = appearance.platterRim;
    final (double, double, double) lensRim = appearance.lensRim;
    final (double, double, double) pill = appearance.pill;
    final (double, double) symbol = appearance.symbol;
    final glassTint = _decorationTint(_glass, platterPixels);
    final restTint = _decorationTint(_indicator, lensPixels);
    final lensTint = _decorationTint(_lens, lensPixels);

    ui.ImageFilter passFilter(int pass) {
      final _BackdropUniforms u = _passes[pass]
        ..pass.set(
          pass.toDouble(),
          diagnostic ? 1 : 0,
          space.pointSize,
          _ovalization,
        )
        ..platter.setRect(platterPixels)
        ..lens.setRect(lensPixels)
        ..optics.set(
          _lift ?? _physics.liftProgress,
          lensScale,
          platterScale,
          _optics.toDouble(),
        )
        ..touch.set(finger.dx, finger.dy, touch == null ? 0 : 1, _physics.press)
        ..inspector.set(
          inspectorPixels.left,
          inspectorPixels.top,
          inspectorPixels.width,
          inspectorPixels.height,
        )
        ..window.set(window.left, window.top, window.width, window.height)
        // The atlas's size as rendered: whole pixels, so at a fractional
        // pixel ratio a little more than the bounds it was drawn in.
        ..content.set(
          barOrigin.dx,
          barOrigin.dy,
          atlas.width / _devicePixelRatio,
          atlas.height / _devicePixelRatio,
        )
        ..tabs.set(
          _physics.tabCenter(0),
          count > 1 ? _physics.tabCenter(1) - _physics.tabCenter(0) : 0,
          count.toDouble(),
          _atlasPitch,
        )
        ..platterTransform.set(
          platterCenter.dx,
          platterCenter.dy,
          drift.dx,
          drift.dy,
        )
        ..platterScale.set(
          squeeze.width,
          squeeze.height,
          _rowHeight,
          _atlasSlot,
        )
        ..glow.set(
          glowPixels.dx,
          glowPixels.dy,
          1 / (2 * glowVariance),
          glowCenter == null ? 0 : glowAlpha * glowPeak,
        )
        ..face.set(face.$1, face.$2, face.$3, face.$4)
        // A decoration's own shadows replace UIKit's.
        ..rim.set(
          platterRim.$1,
          platterRim.$2,
          platterRim.$3,
          _glass.shadows == null ? shadow : 0,
        )
        ..lensRim.set(lensRim.$1, lensRim.$2, lensRim.$3, symbol.$2)
        ..pill.set(pill.$1, pill.$2, pill.$3, symbol.$1)
        // UIKit's selected matrix: half of the glass below plus the tint
        // (held in the atlas's color), less half a unit in the light
        // appearance.
        // .y: where the tabs' content rows start in the bar.
        ..selected.set(
          _contentDark ? 0 : -0.5,
          _rowTop,
          _contrast ? 1 : 0,
          _hasOriginal ? 1 : 0,
        )
        ..setTints(glassTint, restTint, lensTint)
        ..setExtra(
          searchPixels,
          accessoryPixels,
          closePixels,
          contentAlpha,
          selectionAlpha,
          appearance.chroma,
          appearance.refraction,
          _blurSigma * collapsed,
        );
      // Filtered: the lens magnifies the content (the capture the engine
      // samples at the nearest pixel; the shader filters it).
      u.shader.setImageSampler(1, atlas, filterQuality: FilterQuality.low);
      return ui.ImageFilter.shader(u.shader);
    }

    // The decorations' shadows, with the glass's shapes as drawn: the
    // selection's fade as the lens lifts (the resting selection with the
    // lift, the lens's material four times as fast, as UIKit's).
    // All the glass: the platter, and the search circle and the accessory.
    final List<Rect> glass = <Rect>[
      platter,
      if (_hasSearch) shapes.search,
      if (_hasAccessory) shapes.accessory,
      if (shapes.close.width > 1) shapes.close,
    ];
    final List<RRect> glassShapes = <RRect>[
      for (final Rect r in glass)
        RRect.fromRectAndRadius(
          r.shift(offset),
          Radius.circular(r.shortestSide / 2),
        ),
    ];
    final RRect lensShape = RRect.fromRectAndRadius(
      lens.shift(offset),
      Radius.circular(lens.shortestSide / 2),
    );
    final double lift = _lift ?? _physics.liftProgress;
    final double resting = (1 - lift).clamp(0.0, 1.0);
    final double lifted = (4 * lift).clamp(0.0, 1.0);
    // The canvas between the passes' layers.
    Canvas canvas() => context.canvas;

    // The glass's drop shadows go under it, into the backdrop it captures.
    if (!diagnostic) {
      for (final RRect shape in glassShapes) {
        _paintShadows(canvas(), shape, _glass.shadows, 1);
      }
    }

    // Pass 0, the platter's frost, into the backdrop under it (where the
    // bar's glass covers it): UIKit's platter frosts what is below it, then
    // refracts that. The bar's frost and refraction read it from their
    // capture.
    if (_optics & GlassTabBarOptics.platter != 0) {
      _paintFrost(context, offset, glass, platterScale, passFilter(3));
    } else {
      _clearFrost();
    }

    // Pass 1, the bar: takes the capture, before any glass. Its shadows
    // reach past the platter.
    final bool shadows = _optics & GlassTabBarOptics.shadow != 0 && !diagnostic;
    _barClip.layer = context.pushClipRect(
      needsCompositing,
      offset,
      glass
          .reduce((Rect a, Rect b) => a.expandToInclude(b))
          .inflate(shadows ? _shadowMargin : 2),
      (PaintingContext context, Offset offset) {
        final BackdropFilterLayer layer =
            (_barPass.layer ??= BackdropFilterLayer())
              ..filter = passFilter(0)
              ..backdropKey = _sharedCapture;
        context.pushLayer(layer, _paintNothing, offset);
      },
      oldLayer: _barClip.layer,
    );

    // (The bar's shader draws the tabs outside the lens, and the lens's
    // shader those in it, from the content atlas: UIKit colors them from
    // the glass below them.)

    // The fingertip glow, over the platter and its tabs: under the lens,
    // whose shader sees it through its optics.
    if (!diagnostic) {
      for (final RRect shape in glassShapes) {
        _paintInnerShadows(canvas(), shape, _glass.innerShadows, 1);
      }
      _paintShadows(canvas(), lensShape, _indicator.shadows, resting);
      _paintShadows(canvas(), lensShape, _lens.shadows, lifted);
    }
    _paintGlow(context, offset, platter);

    // Pass 2, the lens: the same capture, with the tabs under it lifted into
    // it (drawn by its shader from the content atlas).
    final BackdropKey lensCapture = _shareBackdrop
        ? _sharedCapture
        : _lensOwnCapture;
    if (selectionAlpha <= 0 && !diagnostic) {
      _lensClip.layer = null;
      _lensPass.layer = null;
      _paintExtras(context, offset, shapes);
      _inspectorClip.layer = null;
      _inspectorPass.layer = null;
      return;
    }
    _lensClip.layer = context.pushClipRect(
      needsCompositing,
      offset,
      lens.inflate(shadows ? _lensShadowMargin : 2),
      (PaintingContext context, Offset offset) {
        final BackdropFilterLayer layer =
            (_lensPass.layer ??= BackdropFilterLayer())
              ..filter = passFilter(1)
              ..backdropKey = lensCapture;
        context.pushLayer(layer, _paintNothing, offset);
      },
      oldLayer: _lensClip.layer,
    );

    if (!diagnostic) {
      _paintInnerShadows(canvas(), lensShape, _indicator.innerShadows, resting);
      _paintInnerShadows(canvas(), lensShape, _lens.innerShadows, lifted);
      _paintExtras(context, offset, shapes);
      _inspectorClip.layer = null;
      _inspectorPass.layer = null;
      return;
    }

    // The inspector reads whatever the lens reads.
    _inspectorClip.layer = context.pushClipRect(
      needsCompositing,
      offset,
      inspector,
      (PaintingContext context, Offset offset) {
        final BackdropFilterLayer layer =
            (_inspectorPass.layer ??= BackdropFilterLayer())
              ..filter = passFilter(2)
              ..backdropKey = lensCapture;
        context.pushLayer(layer, (PaintingContext context, Offset offset) {
          _paintInspectorLabels(context.canvas, offset + inspector.topLeft);
        }, offset);
      },
      oldLayer: _inspectorClip.layer,
    );

    // The same field and finger in layout coordinates, as thin dark lines
    // down the middle of the shaders' colored ones.
    _paintLayoutCheck(context.canvas, offset);
  }

  static void _paintNothing(PaintingContext context, Offset offset) {}

  // UIKit's platter frosts what is below it, then refracts that: its glass
  // filter blurs its quarter-scale capture and mixes that into the capture
  // itself, half at the platter's edge and fully 31pt in (measured in the
  // simulator), so a point refracted from deep inside comes out deeply
  // frosted. Here the capture is not scaled down: the
  // heavy blur is drawn first, natively, and the backdrop shader's frost
  // pass draws a light one (for the capture's filtering) over it, fading
  // from half at the edge to none at the middle line. The heavy sigma is in
  // points, fitted to UIKit's frost over stripes. (Through a ShaderMask,
  // which would be simpler, Impeller misplaces a backdrop filter.)
  static const double _frostHeavySigma = 2.9;

  // With Reduce Transparency, UIKit blurs far more (its glass filter's blur
  // radius goes from 0.67 to 36.9) and fully: a sigma that leaves
  // 40pt blocks as faint as UIKit's do, and no light blur.
  static const double _reducedFrostSigma = 20;

  // The frost lies within the platter by this many pixels, under glass the
  // bar draws opaque (as the shader's kFrostInset).
  static const double _frostInset = 2;

  void _paintFrost(
    PaintingContext context,
    Offset offset,
    List<Rect> glass,
    double scale,
    ui.ImageFilter light,
  ) {
    final double inset = _frostInset / _devicePixelRatio;
    final clip = Path();
    for (final Rect r in glass) {
      clip.addRRect(
        RRect.fromRectAndRadius(
          r.deflate(inset),
          Radius.circular(r.shortestSide / 2 - inset),
        ),
      );
    }
    final bool reduced = _appearance.refraction == 0;
    final double sigma =
        (reduced ? _reducedFrostSigma : _frostHeavySigma) * scale;
    final BackdropFilterLayer heavyLayer =
        (_frostHeavy.layer ??= BackdropFilterLayer())
          ..filter = ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma)
          ..backdropKey = _frostCapture;
    final BackdropFilterLayer lightLayer =
        (_frostLight.layer ??= BackdropFilterLayer())
          ..filter = light
          ..backdropKey = _frostCapture;
    _frostClip.layer = context.pushClipPath(
      needsCompositing,
      offset,
      glass.reduce((Rect a, Rect b) => a.expandToInclude(b)),
      clip,
      (PaintingContext context, Offset offset) {
        context.pushLayer(heavyLayer, _paintNothing, offset);
        if (!reduced) {
          context.pushLayer(lightLayer, _paintNothing, offset);
        }
      },
      oldLayer: _frostClip.layer,
    );
  }

  // The search tab's icon in its circle, the selected tab's icon in the
  // minimized bar's circle (fading in as it minimizes), and the accessory's
  // content in its capsule.
  void _paintExtras(
    PaintingContext context,
    Offset offset,
    ({
      Rect platter,
      Rect lens,
      Rect search,
      Rect accessory,
      Rect close,
      Rect circle,
      Rect searchCircle,
      Rect field,
    })
    shapes,
  ) {
    final GlassTabBarMinimize m = _minimize;
    // The accessory as it is.
    if (_accessory case final RenderBox accessory when accessory.hasSize) {
      context.paintChild(
        accessory,
        offset + shapes.accessory.center - accessory.size.center(Offset.zero),
      );
    }
    // The selected tab's icon slides from its tab into the circle, coming
    // in as the tabs go out (UIKit moves it there and crossfades it with the
    // tab's own).
    final Offset tabIcon =
        _platterOrigin +
        Offset(
          _physics.tabCenter(_physics.selectedIndex),
          _rowTop + GlassTabBarPhysics.inset + 20,
        );
    _sliding(
      context,
      offset,
      _minimizedIcon,
      Offset.lerp(tabIcon, shapes.circle.center, m.platterCenter.value)!,
      1,
      m.fade.value,
      0,
      null,
      _minimizedLayers,
    );
    // The search circle's magnifying glass rides the field's leading edge
    // as the circle grows into it, and shrinks to the field's, where the
    // field's text comes in after it.
    final bool rtl = _textDirection == TextDirection.rtl;
    final double open = m.searchOpen.value;
    final double inset = ui.lerpDouble(
      shapes.searchCircle.width / 2,
      _fieldIconInset,
      open,
    )!;
    _sliding(
      context,
      offset,
      _searchIcon,
      _hasField
          ? Offset(
              rtl ? shapes.search.right - inset : shapes.search.left + inset,
              shapes.search.center.dy,
            )
          : shapes.search.center,
      _hasField ? 1 + (_fieldIconScale - 1) * open : 1,
      1,
      0,
      null,
      _searchIconLayers,
    );
    final double searchFade = m.searchFade.value.clamp(0.0, 1.0);
    if (_searchField case final RenderBox field when !shapes.search.isEmpty) {
      _sliding(
        context,
        offset,
        field,
        _fieldOrigin(shapes) + field.size.center(Offset.zero),
        1,
        searchFade,
        _blurSigma * (1 - searchFade),
        RRect.fromRectAndRadius(
          shapes.search,
          Radius.circular(shapes.search.shortestSide / 2),
        ),
        _fieldLayers,
      );
    } else {
      _fieldLayers.clear();
    }
    _sliding(
      context,
      offset,
      _closeIcon,
      shapes.close.center,
      1,
      m.focus.value,
      0,
      null,
      _closeLayers,
    );
  }

  // The field's magnifying glass: centered 23.3pt in from its leading end,
  // 17.5pt to the search tab's 22.3pt.
  static const double _fieldIconInset = 23.3;
  static const double _fieldIconScale = 17.5 / 22.3;

  // Paints [child] centered at [center], scaled, at [shown] opacity,
  // blurred by [blur] (a gaussian sigma), and clipped to [clip].
  void _sliding(
    PaintingContext context,
    Offset offset,
    RenderBox? child,
    Offset center,
    double scale,
    double shown,
    double blur,
    RRect? clip,
    _MorphLayers layers,
  ) {
    if (child == null || !child.hasSize || shown <= 0.004) {
      layers.clear();
      return;
    }
    final Offset at = center - child.size.center(Offset.zero);
    final Matrix4 transform = Matrix4.identity()
      ..translateByDouble(center.dx, center.dy, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1)
      ..translateByDouble(-center.dx, -center.dy, 0, 1);
    void paintChild(PaintingContext context, Offset offset) {
      if (blur < 0.05) {
        layers.blur.layer = null;
        context.paintChild(child, offset + at);
        return;
      }
      final ImageFilterLayer layer = layers.blur.layer ??= ImageFilterLayer();
      layer.imageFilter = ui.ImageFilter.blur(
        sigmaX: blur,
        sigmaY: blur,
        tileMode: TileMode.decal,
      );
      context.pushLayer(
        layer,
        (PaintingContext context, Offset offset) =>
            context.paintChild(child, offset + at),
        offset,
      );
    }

    void faded(PaintingContext context, Offset offset) {
      layers.opacity.layer = context.pushOpacity(
        offset,
        (shown.clamp(0.0, 1.0) * 255).round(),
        paintChild,
        oldLayer: layers.opacity.layer,
      );
    }

    layers.transform.layer = context.pushTransform(
      needsCompositing,
      offset,
      transform,
      (PaintingContext context, Offset offset) {
        if (clip == null) {
          layers.clip.layer = null;
          faded(context, offset);
          return;
        }
        layers.clip.layer = context.pushClipRRect(
          needsCompositing,
          offset,
          clip.outerRect,
          clip,
          faded,
          oldLayer: layers.clip.layer,
        );
      },
      oldLayer: layers.transform.layer,
    );
  }

  // UIKit's crossfade blurs what goes out up to a radius of 4pt: about this
  // gaussian sigma (its radius 2 at quarter scale was a 2.22pt sigma).
  static const double _blurSigma = 3.3;

  final _MorphLayers _minimizedLayers = _MorphLayers();
  final _MorphLayers _searchIconLayers = _MorphLayers();
  final _MorphLayers _fieldLayers = _MorphLayers();
  final _MorphLayers _closeLayers = _MorphLayers();

  void _clearFrost() {
    _frostClip.layer = null;
    _frostHeavy.layer = null;
    _frostLight.layer = null;
  }

  static Paint _shadowPaint(BoxShadow shadow, double opacity) {
    final paint = Paint()
      ..color = shadow.color.withValues(alpha: shadow.color.a * opacity);
    if (shadow.blurSigma > 0) {
      paint.maskFilter = MaskFilter.blur(BlurStyle.normal, shadow.blurSigma);
    }
    return paint;
  }

  // How far [shadow] reaches past its shape.
  static double _reach(BoxShadow shadow) =>
      2 * shadow.blurRadius +
      shadow.spreadRadius.abs() +
      shadow.offset.distance +
      2;

  // Drop shadows of [shape], around it only: the glass shows what is under
  // it, a shadow there included.
  static void _paintShadows(
    Canvas canvas,
    RRect shape,
    List<BoxShadow>? shadows,
    double opacity,
  ) {
    if (shadows == null || shadows.isEmpty || opacity <= 0) {
      return;
    }
    final double reach = shadows.map(_reach).reduce(math.max);
    canvas
      ..save()
      ..clipPath(
        Path()
          ..fillType = PathFillType.evenOdd
          ..addRect(shape.outerRect.inflate(reach))
          ..addRRect(shape),
      );
    for (final BoxShadow shadow in shadows) {
      canvas.drawRRect(
        shape.inflate(shadow.spreadRadius).shift(shadow.offset),
        _shadowPaint(shadow, opacity),
      );
    }
    canvas.restore();
  }

  // Shadows cast inward from [shape]'s edge, over it, as inset shadows: the
  // shape's outside, its edge moved by the offset and in by the spread,
  // blurred into it.
  static void _paintInnerShadows(
    Canvas canvas,
    RRect shape,
    List<BoxShadow>? shadows,
    double opacity,
  ) {
    if (shadows == null || shadows.isEmpty || opacity <= 0) {
      return;
    }
    canvas
      ..save()
      ..clipRRect(shape);
    for (final BoxShadow shadow in shadows) {
      canvas.drawPath(
        Path()
          ..fillType = PathFillType.evenOdd
          ..addRect(shape.outerRect.inflate(_reach(shadow)))
          ..addRRect(shape.deflate(shadow.spreadRadius).shift(shadow.offset)),
        _shadowPaint(shadow, opacity),
      );
    }
    canvas.restore();
  }

  // How far the platter's shadow reaches past it: 39pt past its outline
  // moved 8pt down.
  static const double _shadowMargin = 48;

  // How far the lens's shadow reaches past it: its outline moved 7pt down,
  // and 9.2pt past that.
  static const double _lensShadowMargin = 18;

  // UIKit's LittleGlowView: a white disk under the finger, blurred, clipped
  // to the platter.
  void _paintGlow(PaintingContext context, Offset offset, Rect platter) {
    final Offset? center = _physics.glowCenter;
    final double alpha = _physics.glowAlpha;
    if (_optics & GlassTabBarOptics.press == 0 ||
        center == null ||
        alpha < 1 / 512) {
      _glowClip.layer = null;
      return;
    }
    _glowClip.layer = context.pushClipRRect(
      needsCompositing,
      offset,
      platter,
      RRect.fromRectAndRadius(
        platter,
        Radius.circular(platter.shortestSide / 2),
      ),
      (PaintingContext context, Offset offset) {
        context.canvas.drawCircle(
          offset + center,
          _physics.glowSize / 2,
          Paint()
            ..color = Color.fromRGBO(255, 255, 255, alpha)
            ..maskFilter = MaskFilter.blur(
              BlurStyle.normal,
              _physics.glowSigma,
            ),
        );
      },
      oldLayer: _glowClip.layer,
    );
  }

  final LayerHandle<ClipRRectLayer> _glowClip = LayerHandle<ClipRRectLayer>();

  // The ovalization of UIKit's glass shapes, for the glass's distance field.
  static const double _ovalization = 0.5;
  static const double _inspectorZoom = 2;

  Rect get _inspectorRect =>
      _inspector ?? Rect.fromLTWH(0, -24 - 300, size.width, 300);

  void _paintInspectorLabels(Canvas canvas, Offset origin) {
    final painter = TextPainter(
      text: TextSpan(
        text:
            '${_shareBackdrop ? 'shared capture' : "lens's own capture, taken after the bar's glass"}'
            ', ×2: yellow bar, cyan lens, '
            'pink sampling region, orange sampled band',
        style: const TextStyle(fontSize: 10, color: Color(0xFFFFFFFF)),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: _inspectorRect.width - 12);
    canvas.drawRect(
      Rect.fromLTWH(
        origin.dx,
        origin.dy,
        painter.width + 12,
        painter.height + 8,
      ),
      Paint()..color = const Color(0xB0000000),
    );
    painter.paint(canvas, origin + const Offset(6, 4));
    painter.dispose();
  }

  void _paintLayoutCheck(Canvas canvas, Offset offset) {
    final double hair = 1 / _devicePixelRatio;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = hair
      ..color = const Color(0xFF000000);
    for (final Rect r in <Rect>[_physics.platterRect, _physics.lensRect]) {
      final Rect inset = r.deflate(0.75).shift(offset + _platterOrigin);
      canvas.drawRRect(
        RRect.fromRectAndRadius(inset, Radius.circular(inset.shortestSide / 2)),
        line,
      );
    }
    final Offset? touch = _physics.touch;
    if (touch != null) {
      final Offset t = touch + offset + _platterOrigin;
      canvas
        ..drawLine(t - const Offset(10, 0), t + const Offset(10, 0), line)
        ..drawLine(t - const Offset(0, 10), t + const Offset(0, 10), line);
    }
  }

  // -------------------------------------------------------- the lifted content

  // The selected-style tabs, one per slot of an image, for the lens's shader
  // to grow and lens each about its own center (as UIKit scales its
  // selected tab buttons and lenses them through the lens). Rendered again
  // only when the tabs or their layout change, not every animation frame.
  ui.Image? _contentAtlas;
  ui.Image? _noContent;
  bool _contentDirty = true;

  // Room around each tab for labels wider than the pill.
  static const double _atlasMargin = 12;
  double get _atlasSlot => _physics.pillWidth + 2 * _atlasMargin;
  double get _atlasPitch => _atlasSlot + 2;

  ui.Image _ensureContentAtlas() {
    final int count = _tabCount;
    if (count == 0 || size.isEmpty) {
      return _noContent ??= _emptyImage();
    }
    if (_contentDirty || _contentAtlas == null) {
      _contentDirty = false;
      // A row for each layer (TabLayer.row), a slot in it for each tab;
      // under them, a point high strip of each tab's selected color.
      final Rect bounds = Rect.fromLTWH(
        0,
        0,
        count * _atlasPitch,
        tabLayerCount * _rowHeight + 1,
      );
      final layer = OffsetLayer();
      final context = _AtlasContext(layer, bounds);
      var i = 0;
      RenderBox? child = firstChild;
      while (child != null && i < _extrasStart) {
        context.paintChild(
          child,
          Offset(
            (i % count) * _atlasPitch + _atlasMargin,
            TabLayer.values[i ~/ count].row * _rowHeight,
          ),
        );
        child = childAfter(child);
        i++;
      }
      for (var slot = 0; slot < count && slot < _tints.length; slot++) {
        context.canvas.drawRect(
          Rect.fromLTWH(
            slot * _atlasPitch,
            tabLayerCount * _rowHeight,
            _atlasPitch,
            1,
          ),
          Paint()..color = _tints[slot].withValues(alpha: 1),
        );
      }
      context.finish();
      _contentAtlas?.dispose();
      _contentAtlas = layer.toImageSync(bounds, pixelRatio: _devicePixelRatio);
      layer.dispose();
    }
    return _contentAtlas!;
  }

  static ui.Image _emptyImage() {
    final recorder = ui.PictureRecorder();
    Canvas(recorder);
    final ui.Picture picture = recorder.endRecording();
    final ui.Image image = picture.toImageSync(1, 1);
    picture.dispose();
    return image;
  }

  // ------------------------------------------------------------ the tab items

  // The tabs, inside the platter: normal outside the lens, selected within
  // it.
  void _paintTabs(PaintingContext context, Offset offset, {bool? inside}) {
    final Rect lens = _physics.lensInPlatter.shift(offset);
    final RRect lensShape = RRect.fromRectAndRadius(
      lens,
      Radius.circular(lens.shortestSide / 2),
    );
    final Rect bounds = (offset & size).inflate(40);
    final int count = _tabCount;
    if (inside != true) {
      final outside = Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(bounds)
        ..addRRect(lensShape);
      context.canvas
        ..save()
        ..clipPath(outside);
      _paintChildren(context, offset, count, selected: false);
      context.canvas.restore();
    }
    if (inside != false) {
      context.canvas
        ..save()
        ..clipRRect(lensShape);
      _paintChildren(context, offset, count, selected: true);
      context.canvas.restore();
    }
  }

  void _paintChildren(
    PaintingContext context,
    Offset offset,
    int count, {
    required bool selected,
  }) {
    var i = 0;
    RenderBox? child = firstChild;
    while (child != null && i < _extrasStart) {
      if (TabLayer.values[i ~/ count].selected == selected) {
        context.paintChild(
          child,
          (child.parentData! as _TabParentData).offset + offset,
        );
      }
      child = childAfter(child);
      i++;
    }
  }

  // ------------------------------------------------ the field, drawn flat

  void _paintField(Canvas canvas, Offset offset) {
    final Rect platter = _physics.platterRect.shift(offset);
    final Rect lens = _physics.lensRect.shift(offset);
    final ui.FragmentProgram? program = GlassTabBar._field.program;
    if (program == null) {
      // Until the shader is in: the same shapes, drawn plainly.
      canvas
        ..drawRRect(
          RRect.fromRectAndRadius(
            platter,
            Radius.circular(platter.shortestSide / 2),
          ),
          Paint()..color = const Color(0xFFD6D6D6),
        )
        ..drawRRect(
          RRect.fromRectAndRadius(lens, Radius.circular(lens.shortestSide / 2)),
          Paint()..color = const Color(0xFFBDBDBD),
        );
      return;
    }
    final ui.FragmentShader shader = _fieldShader ??= program.fragmentShader();
    shader
      ..getUniformVec4('uPlatter').set(
        platter.center.dx,
        platter.center.dy,
        platter.width / 2,
        platter.height / 2,
      )
      ..getUniformVec4(
        'uLens',
      ).set(lens.center.dx, lens.center.dy, lens.width / 2, lens.height / 2)
      ..getUniformVec4('uState').set(
        _physics.clear,
        0.5,
        1 / _devicePixelRatio,
        _debugView == GlassTabBarDebugView.normals ? 1 : 0,
      );
    canvas.drawRect(
      platter.expandToInclude(lens).inflate(2),
      Paint()..shader = shader,
    );
  }
}

/// Maps the bar's layout coordinates to the capture's: physical pixels of
/// the pass the backdrop is captured from (the root pass, unless an
/// ancestor draws into its own layer).
class _CaptureSpace {
  _CaptureSpace(this.toRoot, this.devicePixelRatio)
    : pointSize =
          devicePixelRatio *
          (MatrixUtils.transformPoint(toRoot, const Offset(1, 0)) -
                  MatrixUtils.transformPoint(toRoot, Offset.zero))
              .distance;

  final Matrix4 toRoot;
  final double devicePixelRatio;

  /// One layout point, in capture pixels.
  final double pointSize;

  Offset point(Offset p) =>
      MatrixUtils.transformPoint(toRoot, p) * devicePixelRatio;

  Rect rect(Rect r) {
    final Rect g = MatrixUtils.transformRect(toRoot, r);
    return Rect.fromLTRB(
      g.left * devicePixelRatio,
      g.top * devicePixelRatio,
      g.right * devicePixelRatio,
      g.bottom * devicePixelRatio,
    );
  }
}

/// Named bindings into the backdrop shader.
class _BackdropUniforms {
  _BackdropUniforms(this.shader)
    : pass = shader.getUniformVec4('uPass'),
      platter = shader.getUniformVec4('uPlatter'),
      lens = shader.getUniformVec4('uLens'),
      optics = shader.getUniformVec4('uOptics'),
      touch = shader.getUniformVec4('uTouch'),
      inspector = shader.getUniformVec4('uInspector'),
      window = shader.getUniformVec4('uWindow'),
      content = shader.getUniformVec4('uContent'),
      tabs = shader.getUniformVec4('uTabs'),
      platterTransform = shader.getUniformVec4('uPlatterXf'),
      platterScale = shader.getUniformVec4('uPlatterS'),
      glow = shader.getUniformVec4('uGlow'),
      face = shader.getUniformVec4('uFace'),
      rim = shader.getUniformVec4('uRim'),
      lensRim = shader.getUniformVec4('uLensRim'),
      pill = shader.getUniformVec4('uPill'),
      glassTint = _tintSlots(shader, 0),
      restTint = _tintSlots(shader, 1),
      lensTint = _tintSlots(shader, 2),
      selected = shader.getUniformVec4('uSelected'),
      extra = shader.getUniformVec4Array('uExtra');

  final ui.FragmentShader shader;
  final ui.UniformVec4Slot pass;
  final ui.UniformVec4Slot platter;
  final ui.UniformVec4Slot lens;
  final ui.UniformVec4Slot optics;
  final ui.UniformVec4Slot touch;
  final ui.UniformVec4Slot inspector;
  final ui.UniformVec4Slot window;
  final ui.UniformVec4Slot content;
  final ui.UniformVec4Slot tabs;
  final ui.UniformVec4Slot platterTransform;
  final ui.UniformVec4Slot platterScale;
  final ui.UniformVec4Slot glow;
  final ui.UniformVec4Slot face;
  final ui.UniformVec4Slot rim;
  final ui.UniformVec4Slot lensRim;
  final ui.UniformVec4Slot pill;
  final List<ui.UniformVec4Slot> glassTint;
  final List<ui.UniformVec4Slot> restTint;
  final List<ui.UniformVec4Slot> lensTint;
  final ui.UniformVec4Slot selected;
  final ui.UniformArray<ui.UniformVec4Slot> extra;

  /// The glass beside the platter (capture pixels; empty rects for none),
  /// and how much the tabs' content and the selection show.
  void setExtra(
    Rect search,
    Rect accessory,
    Rect close,
    double content,
    double selection,
    double chroma,
    double refraction,
    double blur,
  ) {
    extra[0].setRect(search);
    extra[1].setRect(accessory);
    extra[2].setRect(close);
    extra[3].set(content, selection, chroma, refraction);
    extra[4].set(blur, 0, 0, 0);
  }

  // A tint's slots: at its gradient's start (over white glass, with its
  // alpha, and over black glass), at its end, and its axis.
  // A tint's five slots in uTints (one array: Metal gives each uniform a
  // buffer of its own, and has 31): at its gradient's start (over white
  // glass, with its alpha, and over black glass), at its end, and its axis.
  static List<ui.UniformVec4Slot> _tintSlots(
    ui.FragmentShader shader,
    int tint,
  ) {
    final ui.UniformArray<ui.UniformVec4Slot> all = shader.getUniformVec4Array(
      'uTints',
    );
    return <ui.UniformVec4Slot>[for (var i = 0; i < 5; i++) all[5 * tint + i]];
  }

  /// The platter's, the resting selection's and the lens's tints, each at its
  /// gradient's start and end, along its axis (capture pixels).
  void setTints(
    (GlassTint, GlassTint, Offset, Offset, bool) glass,
    (GlassTint, GlassTint, Offset, Offset, bool) rest,
    (GlassTint, GlassTint, Offset, Offset, bool) lens,
  ) {
    for (final (
          List<ui.UniformVec4Slot> slots,
          (GlassTint, GlassTint, Offset, Offset, bool) t,
        )
        in <
          (
            List<ui.UniformVec4Slot>,
            (GlassTint, GlassTint, Offset, Offset, bool),
          )
        >[(glassTint, glass), (restTint, rest), (lensTint, lens)]) {
      final (
        GlassTint start,
        GlassTint end,
        Offset from,
        Offset to,
        bool paint,
      ) = t;
      slots[0].set(
        start.bright[0],
        start.bright[1],
        start.bright[2],
        start.alpha,
      );
      // .w: painted rather than tinted.
      slots[1].set(start.dark[0], start.dark[1], start.dark[2], paint ? 1 : 0);
      slots[2].set(end.bright[0], end.bright[1], end.bright[2], end.alpha);
      slots[3].set(end.dark[0], end.dark[1], end.dark[2], 0);
      slots[4].set(from.dx, from.dy, to.dx, to.dy);
    }
  }
}

/// Paints the tabs into a layer of their own, for the content atlas.
class _AtlasContext extends PaintingContext {
  _AtlasContext(super.containerLayer, super.estimatedBounds);

  void finish() => stopRecordingIfNeeded();
}

extension on ui.UniformVec4Slot {
  // A rect as its center and half size.
  void setRect(Rect r) =>
      set(r.center.dx, r.center.dy, r.width / 2, r.height / 2);
}

/// The layers a crossfading extra is painted through.
class _MorphLayers {
  final LayerHandle<TransformLayer> transform = LayerHandle<TransformLayer>();
  final LayerHandle<ClipRRectLayer> clip = LayerHandle<ClipRRectLayer>();
  final LayerHandle<OpacityLayer> opacity = LayerHandle<OpacityLayer>();
  final LayerHandle<ImageFilterLayer> blur = LayerHandle<ImageFilterLayer>();

  void clear() {
    transform.layer = null;
    clip.layer = null;
    opacity.layer = null;
    blur.layer = null;
  }
}
