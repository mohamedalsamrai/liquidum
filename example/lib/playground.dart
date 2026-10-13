import 'package:flutter/cupertino.dart';

import 'package:liquidum/liquidum.dart';

import 'feed.dart';
import 'native_tab_bar.dart';
import 'sf_symbol.dart';
import 'tabs.dart';

// A playground for the bar: its colors and appearance changed live, and
// Apple's own bar (on iOS) over the same pages, to compare them.
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
    this.badges = true,
    this.brightness,
    this.adaptive = true,
    this.rtl = false,
  });

  final Color? selectedColor;
  final Color? unselectedColor;
  final bool badges;
  final Brightness? brightness;
  final bool adaptive;
  final bool rtl;

  _Options copyWith({
    Color? Function()? selectedColor,
    Color? Function()? unselectedColor,
    bool? badges,
    Brightness? Function()? brightness,
    bool? adaptive,
    bool? rtl,
  }) => _Options(
    selectedColor: selectedColor == null ? this.selectedColor : selectedColor(),
    unselectedColor: unselectedColor == null
        ? this.unselectedColor
        : unselectedColor(),
    badges: badges ?? this.badges,
    brightness: brightness == null ? this.brightness : brightness(),
    adaptive: adaptive ?? this.adaptive,
    rtl: rtl ?? this.rtl,
  );
}

class Playground extends StatefulWidget {
  const Playground({super.key});

  @override
  State<Playground> createState() => _PlaygroundState();
}

class _PlaygroundState extends State<Playground> {
  final GlassTabController _tabs = GlassTabController();

  /// Whether Apple's native tab bar is shown instead of Liquidum's.
  bool _native = false;

  _Options _options = const _Options();

  @override
  void dispose() {
    _tabs.dispose();
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
        brightness: o.brightness,
        adaptive: o.adaptive,
        tabs: <GlassTab>[
          for (var i = 0; i < tabs.length; i++)
            GlassTab.custom(
              // UIKit's own symbols, as Apple's bar draws them.
              icon: SfSymbol(tabs[i].symbol, fallback: tabs[i].icon),
              label: tabs[i].label,
              badge: _badge(i),
              page: Feed(title: tabs[i].label),
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
                  onValueChanged: (bool? native) =>
                      setState(() => _native = native ?? false),
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
    return CupertinoPopupSurface(
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
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
            ],
          ),
        ),
      ),
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
