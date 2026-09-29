import 'package:flutter/cupertino.dart';

import 'package:liquidum/liquidum.dart';

import 'glass_tab_bar.dart';
import 'native_tab_bar.dart';
import 'sf_symbol.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Glass.precache();
  await SfSymbol.precache(
    _HomePageState._tabs.map((GlassTabItem item) => item.symbol),
  );
  runApp(const ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const CupertinoApp(
      debugShowCheckedModeBanner: false,
      home: HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const _tabs = <GlassTabItem>[
    GlassTabItem(
      icon: CupertinoIcons.house_fill,
      label: 'Home',
      symbol: 'house.fill',
    ),
    GlassTabItem(
      icon: CupertinoIcons.square_grid_2x2_fill,
      label: 'New',
      symbol: 'square.grid.2x2.fill',
    ),
    GlassTabItem(
      icon: CupertinoIcons.dot_radiowaves_left_right,
      label: 'Radio',
      symbol: 'dot.radiowaves.left.and.right',
    ),
    GlassTabItem(
      icon: CupertinoIcons.music_albums_fill,
      label: 'Library',
      symbol: 'music.note.square.stack.fill',
    ),
  ];

  int _selected = 0;

  /// Whether Apple's native tab bar is shown instead of Liquidum's.
  bool _native = false;

  void _select(int index) => setState(() => _selected = index);

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      child: Stack(
        children: <Widget>[
          GlassBackdrop(child: _Feed(title: _tabs[_selected].label)),
          if (_native)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: NativeTabBar.height,
              child: NativeTabBar(
                items: _tabs,
                selectedIndex: _selected,
                onSelected: _select,
              ),
            )
          else
            Positioned(
              left: 21,
              right: 21,
              bottom: 21,
              child: GlassTabBar(
                items: _tabs,
                selectedIndex: _selected,
                onSelected: _select,
              ),
            ),
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
    );
  }
}

/// Colorful, high-contrast content, so the glass has something to bend.
class _Feed extends StatelessWidget {
  const _Feed({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final EdgeInsets padding = MediaQuery.paddingOf(context);
    return CustomScrollView(
      slivers: <Widget>[
        SliverPadding(
          padding: EdgeInsets.fromLTRB(20, padding.top + 24, 20, 12),
          sliver: SliverToBoxAdapter(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.bold,
                color: CupertinoColors.label.resolveFrom(context),
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, padding.bottom + 100),
          sliver: SliverGrid.builder(
            itemCount: 24,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 0.8,
            ),
            itemBuilder: (BuildContext context, int index) =>
                _Card(index: index),
          ),
        ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    final double hue = (index * 47) % 360;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[
                  HSVColor.fromAHSV(1, hue, 0.75, 0.95).toColor(),
                  HSVColor.fromAHSV(1, (hue + 60) % 360, 0.9, 0.55).toColor(),
                ],
              ),
            ),
            child: Center(
              child: Text(
                '${index + 1}',
                style: const TextStyle(
                  fontSize: 64,
                  fontWeight: FontWeight.w800,
                  color: Color(0xE6FFFFFF),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Album ${index + 1}',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: CupertinoColors.label.resolveFrom(context),
          ),
        ),
        Text(
          'Artist',
          style: TextStyle(
            fontSize: 15,
            color: CupertinoColors.secondaryLabel.resolveFrom(context),
          ),
        ),
      ],
    );
  }
}
