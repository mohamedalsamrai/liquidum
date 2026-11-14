import 'package:flutter/cupertino.dart';

import 'package:liquidum/liquidum.dart';

import 'feed.dart';
import 'native_tab_bar.dart';
import 'sf_symbol.dart';
import 'tabs.dart';

// A playground for the bar: its colors and appearance changed live, the
// search tab, the bottom accessory and minimizing turned on and off, and
// Apple's own bar (on iOS) over the same pages, to compare them. Its Glass
// tab tries Liquidum's other glass over the same content: glass buttons,
// interactive glass and a glass group.
// Run with `flutter run -t lib/playground.dart`.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SfSymbol.precache(tabs.map((TabSpec tab) => tab.symbol));
  runApp(
    const CupertinoApp(debugShowCheckedModeBanner: false, home: Playground()),
  );
}

/// What the customization panel changes.
class _Options {
  const _Options({
    this.selectedColor,
    this.unselectedColor,
    this.glassColor,
    this.indicatorColor,
    this.lensColor,
    this.badges = true,
    this.brightness,
    this.adaptive = true,
    this.rtl = false,
    this.search = false,
    this.accessory = false,
    this.minimizeOnScroll = false,
    this.reduceTransparency = false,
    this.buttonStyle = GlassStyle.regular,
    this.buttonSize = GlassButtonSize.medium,
    this.buttonTint,
    this.buttonsEnabled = true,
  });

  final Color? selectedColor;
  final Color? unselectedColor;
  final Color? glassColor;
  final Color? indicatorColor;
  final Color? lensColor;
  final bool badges;
  final Brightness? brightness;
  final bool adaptive;
  final bool rtl;
  final bool search;
  final bool accessory;
  final bool minimizeOnScroll;
  final bool reduceTransparency;

  // The Glass tab's buttons.
  final GlassStyle buttonStyle;
  final GlassButtonSize buttonSize;
  final Color? buttonTint;
  final bool buttonsEnabled;

  _Options copyWith({
    Color? Function()? selectedColor,
    Color? Function()? unselectedColor,
    Color? Function()? glassColor,
    Color? Function()? indicatorColor,
    Color? Function()? lensColor,
    bool? badges,
    Brightness? Function()? brightness,
    bool? adaptive,
    bool? rtl,
    bool? search,
    bool? accessory,
    bool? minimizeOnScroll,
    bool? reduceTransparency,
    GlassStyle? buttonStyle,
    GlassButtonSize? buttonSize,
    Color? Function()? buttonTint,
    bool? buttonsEnabled,
  }) => _Options(
    selectedColor: selectedColor == null ? this.selectedColor : selectedColor(),
    unselectedColor: unselectedColor == null
        ? this.unselectedColor
        : unselectedColor(),
    glassColor: glassColor == null ? this.glassColor : glassColor(),
    indicatorColor: indicatorColor == null
        ? this.indicatorColor
        : indicatorColor(),
    lensColor: lensColor == null ? this.lensColor : lensColor(),
    badges: badges ?? this.badges,
    brightness: brightness == null ? this.brightness : brightness(),
    adaptive: adaptive ?? this.adaptive,
    rtl: rtl ?? this.rtl,
    search: search ?? this.search,
    accessory: accessory ?? this.accessory,
    minimizeOnScroll: minimizeOnScroll ?? this.minimizeOnScroll,
    reduceTransparency: reduceTransparency ?? this.reduceTransparency,
    buttonStyle: buttonStyle ?? this.buttonStyle,
    buttonSize: buttonSize ?? this.buttonSize,
    buttonTint: buttonTint == null ? this.buttonTint : buttonTint(),
    buttonsEnabled: buttonsEnabled ?? this.buttonsEnabled,
  );
}

class Playground extends StatefulWidget {
  const Playground({super.key});

  @override
  State<Playground> createState() => _PlaygroundState();
}

class _PlaygroundState extends State<Playground> {
  final GlassTabController _tabs = GlassTabController();

  /// The Glass tab's index, after the feed tabs (Liquidum's bar only).
  static final int _glassTab = tabs.length;

  /// The last feed tab, to go back to when the search or Glass tab goes.
  int _lastTab = 0;

  /// The search tab's field.
  final TextEditingController _query = TextEditingController();

  /// Whether Apple's native tab bar is shown instead of Liquidum's.
  bool _native = false;

  _Options _options = const _Options();

  @override
  void initState() {
    super.initState();
    _tabs.addListener(() {
      if (_tabs.index < tabs.length) {
        _lastTab = _tabs.index;
      }
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    _query.dispose();
    super.dispose();
  }

  void _customize() {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (BuildContext context) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setSheetState) =>
            _OptionsSheet(
              options: _options,
              onChanged: (_Options options) {
                setState(() => _options = options);
                setSheetState(() {});
                if (!options.search) {
                  _offExtras();
                }
              },
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final _Options o = _options;
    Widget body;
    if (_native) {
      body = Stack(
        children: <Widget>[
          GlassBackdrop(
            child: ListenableBuilder(
              listenable: _tabs,
              builder: (BuildContext context, _) =>
                  Feed(title: tabs[_tabs.index].label),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: NativeTabBar.height,
            child: ListenableBuilder(
              listenable: _tabs,
              builder: (BuildContext context, _) => NativeTabBar(
                items: tabs,
                selectedIndex: _tabs.index,
                onSelected: (int i) => _tabs.index = i,
                tint: o.selectedColor,
                badges: <String?>[
                  for (var i = 0; i < tabs.length; i++) _badge(i),
                ],
              ),
            ),
          ),
        ],
      );
    } else {
      body = GlassTabScaffold(
        controller: _tabs,
        selectedColor: o.selectedColor,
        unselectedColor: o.unselectedColor,
        glassColor: o.glassColor,
        indicatorColor: o.indicatorColor,
        lensColor: o.lensColor,
        brightness: o.brightness,
        adaptive: o.adaptive,
        accessory: o.accessory ? const _NowPlaying() : null,
        minimizeOnScroll: o.minimizeOnScroll,
        reduceTransparency: o.reduceTransparency,
        tabs: <GlassTab>[
          for (var i = 0; i < tabs.length; i++)
            GlassTab.custom(
              // UIKit's own symbols, as Apple's bar draws them.
              icon: SfSymbol(tabs[i].symbol, fallback: tabs[i].icon),
              label: tabs[i].label,
              badge: _badge(i),
              page: Feed(title: tabs[i].label),
            ),
          GlassTab.custom(
            icon: const SfSymbol(
              'drop.fill',
              fallback: CupertinoIcons.drop_fill,
            ),
            label: 'Glass',
            page: _GlassPage(options: o),
          ),
          if (o.search)
            GlassTab.search(
              controller: _query,
              page: ListenableBuilder(
                listenable: _query,
                builder: (BuildContext context, _) =>
                    Feed(title: 'Search', query: _query.text),
              ),
            ),
        ],
      );
    }
    return CupertinoPageScaffold(
      child: Directionality(
        textDirection: o.rtl ? TextDirection.rtl : TextDirection.ltr,
        child: Stack(
          children: <Widget>[
            Positioned.fill(child: body),
            Positioned(
              top: MediaQuery.paddingOf(context).top + 8,
              left: 16,
              child: CupertinoButton.tinted(
                sizeStyle: CupertinoButtonSize.small,
                onPressed: _customize,
                child: const Text('Customize'),
              ),
            ),
            if (NativeTabBar.isAvailable)
              Positioned(
                top: MediaQuery.paddingOf(context).top + 8,
                right: 16,
                child: CupertinoSlidingSegmentedControl<bool>(
                  groupValue: _native,
                  onValueChanged: (bool? native) {
                    // Apple's bar here has no search or Glass tab.
                    if (native ?? false) {
                      _offExtras(all: true);
                    }
                    setState(() => _native = native ?? false);
                  },
                  children: const <bool, Widget>{
                    false: Text('Liquidum'),
                    true: Text('Apple'),
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  // Back from the search tab (or, with [all], the Glass tab too) to the
  // feed tab before it, when it goes.
  void _offExtras({bool all = false}) {
    if (_tabs.index > _glassTab || (all && _tabs.index == _glassTab)) {
      _tabs.index = _lastTab;
    }
  }

  String? _badge(int i) => !_options.badges
      ? null
      : switch (i) {
          1 => '3',
          3 => '12',
          _ => null,
        };
}

/// Controls for the bar's style, to try them out.
class _OptionsSheet extends StatelessWidget {
  const _OptionsSheet({required this.options, required this.onChanged});

  final _Options options;
  final ValueChanged<_Options> onChanged;

  static const List<Color?> _colors = <Color?>[
    null,
    CupertinoColors.systemPink,
    CupertinoColors.systemOrange,
    CupertinoColors.systemGreen,
    CupertinoColors.systemPurple,
    Color(0xFF000000),
  ];

  @override
  Widget build(BuildContext context) {
    final _Options o = options;
    final MediaQueryData media = MediaQuery.of(context);
    return CupertinoPopupSurface(
      // Clear of the top of the screen, to tap there to close it too.
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: media.size.height - media.padding.top - 24,
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 8, 0),
                child: Row(
                  children: <Widget>[
                    const Expanded(
                      child: Text(
                        'Customize',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    CupertinoButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Done'),
                    ),
                  ],
                ),
              ),
              Flexible(child: _controls(context, o)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _controls(BuildContext context, _Options o) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const _Heading('Selected color'),
          _Swatches(
            colors: _colors,
            value: o.selectedColor,
            onChanged: (Color? c) =>
                onChanged(o.copyWith(selectedColor: () => c)),
          ),
          const _Heading('Unselected color (UIKit: always adaptive)'),
          _Swatches(
            colors: _colors,
            value: o.unselectedColor,
            onChanged: (Color? c) =>
                onChanged(o.copyWith(unselectedColor: () => c)),
          ),
          const _Heading('Bar glass'),
          _Swatches(
            colors: _colors,
            value: o.glassColor,
            onChanged: (Color? c) => onChanged(o.copyWith(glassColor: () => c)),
          ),
          const _Heading('Selection at rest'),
          _Swatches(
            colors: _colors,
            value: o.indicatorColor,
            onChanged: (Color? c) =>
                onChanged(o.copyWith(indicatorColor: () => c)),
          ),
          const _Heading('Lens while moving'),
          _Swatches(
            colors: _colors,
            value: o.lensColor,
            onChanged: (Color? c) => onChanged(o.copyWith(lensColor: () => c)),
          ),
          const _Heading('Appearance'),
          CupertinoSlidingSegmentedControl<int>(
            groupValue: switch (o.brightness) {
              null => 0,
              Brightness.light => 1,
              Brightness.dark => 2,
            },
            onValueChanged: (int? v) => onChanged(
              o.copyWith(
                brightness: () => switch (v) {
                  1 => Brightness.light,
                  2 => Brightness.dark,
                  _ => null,
                },
              ),
            ),
            children: const <int, Widget>{
              0: Text('System'),
              1: Text('Light'),
              2: Text('Dark'),
            },
          ),
          _Switch(
            label: 'Adapts to the content behind it',
            value: o.adaptive,
            onChanged: (bool v) => onChanged(o.copyWith(adaptive: v)),
          ),
          _Switch(
            label: 'Badges',
            value: o.badges,
            onChanged: (bool v) => onChanged(o.copyWith(badges: v)),
          ),
          _Switch(
            label: 'Right to left',
            value: o.rtl,
            onChanged: (bool v) => onChanged(o.copyWith(rtl: v)),
          ),
          const _Heading("iOS 26's extras (Liquidum's bar only)"),
          _Switch(
            label: 'Search tab',
            value: o.search,
            onChanged: (bool v) => onChanged(o.copyWith(search: v)),
          ),
          _Switch(
            label: 'Bottom accessory',
            value: o.accessory,
            onChanged: (bool v) => onChanged(o.copyWith(accessory: v)),
          ),
          _Switch(
            label: 'Minimize on scroll',
            value: o.minimizeOnScroll,
            onChanged: (bool v) => onChanged(o.copyWith(minimizeOnScroll: v)),
          ),
          _Switch(
            label: 'Reduce Transparency',
            value: o.reduceTransparency,
            onChanged: (bool v) => onChanged(o.copyWith(reduceTransparency: v)),
          ),
          const _Heading('Glass buttons (the Glass tab)'),
          CupertinoSlidingSegmentedControl<GlassStyle>(
            groupValue: o.buttonStyle,
            onValueChanged: (GlassStyle? v) =>
                onChanged(o.copyWith(buttonStyle: v)),
            children: const <GlassStyle, Widget>{
              GlassStyle.regular: Text('Regular'),
              GlassStyle.clear: Text('Clear'),
            },
          ),
          const SizedBox(height: 10),
          CupertinoSlidingSegmentedControl<GlassButtonSize>(
            groupValue: o.buttonSize,
            onValueChanged: (GlassButtonSize? v) =>
                onChanged(o.copyWith(buttonSize: v)),
            children: const <GlassButtonSize, Widget>{
              GlassButtonSize.mini: Text('Mini'),
              GlassButtonSize.small: Text('Small'),
              GlassButtonSize.medium: Text('Medium'),
              GlassButtonSize.large: Text('Large'),
            },
          ),
          const _Heading('Prominent fill'),
          _Swatches(
            colors: _colors,
            value: o.buttonTint,
            onChanged: (Color? c) => onChanged(o.copyWith(buttonTint: () => c)),
          ),
          _Switch(
            label: 'Enabled',
            value: o.buttonsEnabled,
            onChanged: (bool v) => onChanged(o.copyWith(buttonsEnabled: v)),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              'Increase Contrast and Reduce Motion follow the '
              "system's settings.",
              style: TextStyle(
                fontSize: 13,
                color: CupertinoColors.secondaryLabel.resolveFrom(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Liquidum's other glass over the feed: UIKit's glass buttons, glass that
/// responds to a finger, and a glass group whose glass melts together.
class _GlassPage extends StatefulWidget {
  const _GlassPage({required this.options});

  final _Options options;

  @override
  State<_GlassPage> createState() => _GlassPageState();
}

class _GlassPageState extends State<_GlassPage> {
  // The glass group's extra glass, shown and hidden by its button.
  bool _more = false;
  int _taps = 0;
  // The lens controls' values.
  bool _on = true;
  double _amount = 0.4;
  DateTime _when = DateTime.now();
  String _segment = 'One';
  String _sort = 'Name';
  final Set<int> _favorites = <int>{};

  @override
  Widget build(BuildContext context) {
    final _Options o = widget.options;
    final VoidCallback? tap = o.buttonsEnabled
        ? () => setState(() => _taps++)
        : null;
    GlassButton button({
      String? label,
      IconData? icon,
      bool prominent = false,
    }) => GlassButton(
      label: label,
      icon: icon,
      prominent: prominent,
      style: o.buttonStyle,
      size: o.buttonSize,
      tint: o.buttonTint,
      onPressed: tap,
    );
    final TextStyle caption = TextStyle(
      fontSize: 13,
      color: CupertinoColors.label.resolveFrom(context),
    );
    return Stack(
      children: <Widget>[
        // The content the glass floats over, on the page's background:
        // scroll it under the glass.
        Positioned.fill(
          child: GlassBackdrop(
            child: ColoredBox(
              color: CupertinoColors.systemBackground.resolveFrom(context),
              child: const Feed(title: 'Glass'),
            ),
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          top: MediaQuery.paddingOf(context).top + 120,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  button(label: 'Button'),
                  button(icon: CupertinoIcons.add),
                  button(label: 'Add', icon: CupertinoIcons.add),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  button(label: 'Prominent', prominent: true),
                  button(icon: CupertinoIcons.heart_fill, prominent: true),
                  Text('Taps: $_taps', style: caption),
                ],
              ),
              const SizedBox(height: 24),
              // Any glass can respond to a finger: press it, drag out of it.
              Glass(
                interactive: true,
                radius: 28,
                child: SizedBox(
                  height: 110,
                  width: double.infinity,
                  child: Center(
                    child: Text(
                      'Interactive glass: press and drag',
                      style: caption,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              // The lens controls: their thumb and selection are the lens.
              Row(
                children: <Widget>[
                  GlassSwitch(
                    value: _on,
                    activeColor: o.buttonTint,
                    onChanged: o.buttonsEnabled
                        ? (bool v) => setState(() => _on = v)
                        : null,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: GlassSlider(
                      value: _amount,
                      activeColor: o.buttonTint,
                      onChanged: o.buttonsEnabled
                          ? (double v) => setState(() => _amount = v)
                          : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: GlassSegmentedControl<String>(
                  children: const <String, Widget>{
                    'One': Text('One'),
                    'Two': Text('Two'),
                    'Three': Text('Three'),
                  },
                  groupValue: _segment,
                  onValueChanged: o.buttonsEnabled
                      ? (String v) => setState(() => _segment = v)
                      : null,
                ),
              ),
              const SizedBox(height: 24),
              // Pages with UIKit's bars: a navigation bar, a toolbar or a
              // search field, over content that scrolls under them.
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: <Widget>[
                  GlassButton(
                    label: 'Page with bars',
                    onPressed: () =>
                        Navigator.of(context, rootNavigator: true).push(
                          CupertinoPageRoute<void>(
                            builder: (BuildContext context) =>
                                const _BarsPage(),
                          ),
                        ),
                  ),
                  // A menu: a touch opens it out of the button with
                  // UIKit's liquid morph.
                  GlassButton(
                    label: 'Sort',
                    icon: CupertinoIcons.arrow_up_arrow_down,
                    menu: <GlassMenuItem>[
                      for (final String by in const <String>[
                        'Name',
                        'Date',
                        'Size',
                      ])
                        GlassMenuItem(
                          label: by,
                          checked: _sort == by,
                          onPressed: () => setState(() => _sort = by),
                        ),
                      const GlassMenuItem.divider(),
                      GlassMenuItem.submenu(
                        label: 'Show',
                        items: <GlassMenuItem>[
                          GlassMenuItem(label: 'All', onPressed: () {}),
                          GlassMenuItem(label: 'Favorites', onPressed: () {}),
                        ],
                      ),
                      GlassMenuItem(
                        label: 'Delete all',
                        icon: CupertinoIcons.trash,
                        destructive: true,
                        onPressed: () {},
                      ),
                    ],
                  ),
                  GlassButton(
                    label: 'Page with search',
                    onPressed: () =>
                        Navigator.of(context, rootNavigator: true).push(
                          CupertinoPageRoute<void>(
                            builder: (BuildContext context) =>
                                const _BarsPage(search: true),
                          ),
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              // A glass group: glass within its spacing melts together, and
              // glass appearing in it grows out of its neighbors.
              Row(
                children: <Widget>[
                  GlassGroup(
                    spacing: 20,
                    child: Row(
                      children: <Widget>[
                        GlassButton(
                          icon: _more
                              ? CupertinoIcons.xmark
                              : CupertinoIcons.ellipsis,
                          onPressed: () => setState(() => _more = !_more),
                        ),
                        for (final IconData icon in const <IconData>[
                          CupertinoIcons.share,
                          CupertinoIcons.bookmark,
                          CupertinoIcons.trash,
                        ]) ...<Widget>[
                          const SizedBox(width: 6),
                          Glass(
                            visible: _more,
                            child: SizedBox.square(
                              dimension: 34.33,
                              child: _more ? Icon(icon, size: 18) : null,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const Spacer(),
                  // Context menus: a long press lifts a tile over the
                  // dimmed screen and grows its menu out of it.
                  for (final (int i, Color color) in const <(int, Color)>[
                    (0, Color(0xFF0088FF)),
                    (1, Color(0xFFFF8D28)),
                    (2, Color(0xFF34C759)),
                  ]) ...<Widget>[
                    const SizedBox(width: 8),
                    SizedBox.square(
                      dimension: 56,
                      child: GlassContextMenu(
                        items: <GlassMenuItem>[
                          GlassMenuItem(
                            label: 'Favorite',
                            icon: CupertinoIcons.heart,
                            checked: _favorites.contains(i),
                            onPressed: () => setState(
                              () => _favorites.contains(i)
                                  ? _favorites.remove(i)
                                  : _favorites.add(i),
                            ),
                          ),
                          GlassMenuItem(
                            label: 'Copy',
                            icon: CupertinoIcons.doc_on_doc,
                            onPressed: () {},
                          ),
                          GlassMenuItem(
                            label: 'Share',
                            icon: CupertinoIcons.share,
                            onPressed: () {},
                          ),
                          const GlassMenuItem.divider(),
                          GlassMenuItem(
                            label: 'Delete',
                            icon: CupertinoIcons.trash,
                            destructive: true,
                            onPressed: () {},
                          ),
                        ],
                        child: ClipRSuperellipse(
                          borderRadius: const BorderRadius.all(
                            Radius.circular(12),
                          ),
                          child: ColoredBox(
                            color: color,
                            child: Icon(
                              _favorites.contains(i)
                                  ? CupertinoIcons.heart_fill
                                  : CupertinoIcons.photo,
                              color: const Color(0xFFFFFFFF),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              // The edit menu: select a word for Cut, Copy, Paste... on
              // glass (the chevron opens the full menu).
              const CupertinoTextField(
                placeholder: 'Select text for the edit menu',
                contextMenuBuilder: GlassEditMenu.builder,
              ),
              const SizedBox(height: 12),
              // The compact date picker: the calendar, or the time wheels,
              // on glass.
              Align(
                alignment: Alignment.centerLeft,
                child: GlassDatePicker(
                  value: _when,
                  mode: GlassDatePickerMode.dateAndTime,
                  onChanged: (DateTime d) => setState(() => _when = d),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A page with UIKit's bars over a colorful list: a large title, a back
/// button, actions and a toolbar, or a search field.
class _BarsPage extends StatefulWidget {
  const _BarsPage({this.search = false});

  final bool search;

  @override
  State<_BarsPage> createState() => _BarsPageState();
}

class _BarsPageState extends State<_BarsPage> {
  String _query = '';
  int _added = 0;

  @override
  Widget build(BuildContext context) {
    final List<int> rows = <int>[
      for (var i = 0; i < 40 + _added; i++)
        if ('Album ${i + 1}'.toLowerCase().contains(_query.toLowerCase())) i,
    ];
    return GlassPage(
      title: widget.search ? 'Search' : 'Albums',
      largeTitle: true,
      onBack: () => Navigator.of(context).pop(),
      actions: widget.search
          ? const <GlassBarItem>[]
          : <GlassBarItem>[
              GlassBarItem(
                icon: CupertinoIcons.ellipsis,
                menu: <GlassMenuItem>[
                  GlassMenuItem(
                    label: 'Share',
                    icon: CupertinoIcons.share,
                    onPressed: () {},
                  ),
                  GlassMenuItem(
                    label: 'Favorite',
                    icon: CupertinoIcons.star,
                    onPressed: () {},
                  ),
                  const GlassMenuItem.divider(),
                  GlassMenuItem(
                    label: 'Delete',
                    icon: CupertinoIcons.trash,
                    destructive: true,
                    onPressed: () {},
                  ),
                ],
              ),
              GlassBarItem(
                icon: CupertinoIcons.add,
                onPressed: () => setState(() => _added++),
              ),
            ],
      toolbar: widget.search
          ? const <GlassBarItem>[]
          : <GlassBarItem>[
              GlassBarItem(icon: CupertinoIcons.trash, onPressed: () {}),
              const GlassBarItem.space(),
              GlassBarItem(icon: CupertinoIcons.share, onPressed: () {}),
              const GlassBarItem.space(),
              GlassBarItem(
                label: 'Done',
                prominent: true,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
      onSearchChanged: widget.search
          ? (String q) => setState(() => _query = q)
          : null,
      child: ListView.builder(
        itemCount: rows.length,
        itemBuilder: (BuildContext context, int index) {
          final int i = rows[index];
          return Container(
            height: 64,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: <Widget>[
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: HSVColor.fromAHSV(
                      1,
                      (i * 47) % 360 * 1.0,
                      0.6,
                      0.95,
                    ).toColor(),
                  ),
                ),
                const SizedBox(width: 14),
                Text(
                  'Album ${i + 1}',
                  style: TextStyle(
                    fontSize: 17,
                    color: CupertinoColors.label.resolveFrom(context),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// A now-playing control for the bottom accessory, as Apple Music's.
class _NowPlaying extends StatefulWidget {
  const _NowPlaying();

  @override
  State<_NowPlaying> createState() => _NowPlayingState();
}

class _NowPlayingState extends State<_NowPlaying> {
  bool _playing = false;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // Album 7's art, as the feed draws it.
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                const HSVColor.fromAHSV(1, 282, 0.75, 0.95).toColor(),
                const HSVColor.fromAHSV(1, 342, 0.9, 0.55).toColor(),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        const Text('Album 7'),
        const SizedBox(width: 20),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _playing = !_playing),
          child: Icon(
            _playing ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill,
          ),
        ),
        const SizedBox(width: 16),
        const Icon(CupertinoIcons.forward_fill),
      ],
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: CupertinoColors.secondaryLabel.resolveFrom(context),
        ),
      ),
    );
  }
}

class _Swatches extends StatelessWidget {
  const _Swatches({
    required this.colors,
    required this.value,
    required this.onChanged,
  });

  final List<Color?> colors;
  final Color? value;
  final ValueChanged<Color?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      children: <Widget>[
        for (final Color? c in colors)
          GestureDetector(
            onTap: () => onChanged(c),
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: c == null
                    ? null
                    : CupertinoDynamicColor.resolve(c, context),
                border: Border.all(
                  width: c == value ? 3 : 1,
                  color: CupertinoColors.label.resolveFrom(context),
                ),
              ),
              child: c == null
                  ? const Center(
                      child: Text('—', style: TextStyle(fontSize: 12)),
                    )
                  : null,
            ),
          ),
      ],
    );
  }
}

class _Switch extends StatelessWidget {
  const _Switch({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label)),
          CupertinoSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}
