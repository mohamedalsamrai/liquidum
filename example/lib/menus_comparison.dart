// Liquidum's side of the menus comparison: glass buttons with menus laid out
// as the research catalog's native menus page, from the same options in
// `<tmp>/comparison.txt`:
//
//   menus|menusnav [items=<list>] [bg=<background>] [style=dark]
//
// Items are "Title", "Title/symbol", "Title/symbol/d" (destructive),
// "Title/symbol/c" (checked), ">Title" (a submenu of three), "-" a divider.
// Buttons: "Menu" at 20,200; an ellipsis at 200,200; a plus at the right
// edge; "Bottom" at 20,820; a prominent button at the bottom right.
// `menusnav`: three GlassPages pushed (First, Second, Third), the last with
// an ellipsis item whose menu is the items (the back button's long press
// lists the pages under it). Writes
// `<tmp>/ready.txt` 2s after the first frame.

import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:liquidum/liquidum.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Glass.precache();
  final file = File('${Directory.systemTemp.path}/comparison.txt');
  final List<String> config = file.existsSync()
      ? file.readAsStringSync().trim().split(' ')
      : <String>['menus'];
  final Map<String, String> options = <String, String>{
    for (final String f in config.skip(1))
      f.split('=').first: f.contains('=')
          ? f.substring(f.indexOf('=') + 1)
          : '',
  };
  final ready = File('${Directory.systemTemp.path}/ready.txt');
  if (ready.existsSync()) {
    ready.deleteSync();
  }
  WidgetsBinding.instance.addPostFrameCallback((_) {
    Timer(const Duration(seconds: 2), () => ready.writeAsStringSync('ready'));
  });
  runApp(
    config.first == 'menusnav'
        ? MenusNavComparison(options: options)
        : MenusComparison(options: options),
  );
}

const Map<String, IconData> _symbols = <String, IconData>{
  'plus': CupertinoIcons.add,
  'ellipsis': CupertinoIcons.ellipsis,
  'trash': CupertinoIcons.trash,
  'square.and.arrow.up': CupertinoIcons.share,
  'doc.on.doc': CupertinoIcons.doc_on_doc,
  'star': CupertinoIcons.star,
  'folder': CupertinoIcons.folder,
};

List<GlassMenuItem> _menu(String spec) => <GlassMenuItem>[
  for (final String raw in spec.split(','))
    if (raw == '-')
      const GlassMenuItem.divider()
    else if (raw.startsWith('>'))
      GlassMenuItem.submenu(
        label: raw.substring(1).replaceAll('_', ' '),
        items: <GlassMenuItem>[
          for (final String t in <String>['Alpha', 'Beta', 'Gamma'])
            GlassMenuItem(label: t, onPressed: () {}),
        ],
      )
    else
      () {
        final List<String> p = raw.split('/');
        return GlassMenuItem(
          label: p[0].replaceAll('_', ' '),
          icon: p.length > 1 && p[1].isNotEmpty
              ? _symbols[p[1]] ?? CupertinoIcons.circle
              : null,
          destructive: p.length > 2 && p[2] == 'd',
          checked: p.length > 2 && p[2] == 'c',
          onPressed: () {},
        );
      }(),
];

class MenusComparison extends StatelessWidget {
  const MenusComparison({super.key, required this.options});

  final Map<String, String> options;

  @override
  Widget build(BuildContext context) {
    final Map<String, String> o = options;
    final bool dark = o['style'] == 'dark';
    final List<GlassMenuItem> items = _menu(o['items'] ?? 'One,Two');
    return CupertinoApp(
      debugShowCheckedModeBanner: false,
      theme: CupertinoThemeData(
        brightness: dark ? Brightness.dark : Brightness.light,
      ),
      builder: (BuildContext context, Widget? child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          platformBrightness: dark ? Brightness.dark : Brightness.light,
        ),
        child: child!,
      ),
      home: Builder(
        builder: (BuildContext context) {
          final double w = MediaQuery.sizeOf(context).width;
          return Stack(
            children: <Widget>[
              Positioned.fill(
                child: CustomPaint(painter: _Pattern(o['bg'] ?? 'blocks')),
              ),
              Positioned(
                left: 20,
                top: 200,
                child: GlassButton(label: 'Menu', menu: items),
              ),
              Positioned(
                left: 200,
                top: 200,
                child: GlassButton(icon: CupertinoIcons.ellipsis, menu: items),
              ),
              Positioned(
                left: w - 20 - 34.33,
                top: 200,
                child: GlassButton(icon: CupertinoIcons.add, menu: items),
              ),
              Positioned(
                left: 20,
                top: 820,
                child: GlassButton(label: 'Bottom', menu: items),
              ),
              Positioned(
                right: 20,
                top: 820,
                child: GlassButton(
                  label: 'Prominent',
                  prominent: true,
                  menu: items,
                ),
              ),
              const Positioned(
                left: 20,
                top: 450,
                height: 44,
                child: ColoredBox(
                  color: Color(0xFFFFFFFF),
                  child: Center(
                    child: Text(
                      '  Long-press for a context menu  ',
                      style: TextStyle(
                        fontSize: 17,
                        color: Color(0xFF000000),
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class MenusNavComparison extends StatefulWidget {
  const MenusNavComparison({super.key, required this.options});

  final Map<String, String> options;

  @override
  State<MenusNavComparison> createState() => _MenusNavComparisonState();
}

class _MenusNavComparisonState extends State<MenusNavComparison> {
  final GlobalKey<NavigatorState> _navigator = GlobalKey<NavigatorState>();

  Widget _page(String title, {bool back = true, bool items = false}) => Builder(
    builder: (BuildContext context) => GlassPage(
      title: title,
      onBack: back ? () => Navigator.pop(context) : null,
      actions: <GlassBarItem>[
        if (items)
          GlassBarItem(
            icon: CupertinoIcons.ellipsis,
            menu: _menu(widget.options['items'] ?? 'One,Two'),
          ),
      ],
      child: CustomPaint(
        painter: _Pattern(widget.options['bg'] ?? 'blocks'),
        size: Size.infinite,
      ),
    ),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _navigator.currentState!
        ..push(
          PageRouteBuilder<void>(pageBuilder: (_, _, _) => _page('Second')),
        )
        ..push(
          PageRouteBuilder<void>(
            pageBuilder: (_, _, _) => _page('Third', items: true),
          ),
        );
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool dark = widget.options['style'] == 'dark';
    return CupertinoApp(
      navigatorKey: _navigator,
      debugShowCheckedModeBanner: false,
      theme: CupertinoThemeData(
        brightness: dark ? Brightness.dark : Brightness.light,
      ),
      builder: (BuildContext context, Widget? child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          platformBrightness: dark ? Brightness.dark : Brightness.light,
        ),
        child: child!,
      ),
      home: _page('First', back: false),
    );
  }
}

/// The catalog's PatternView: 44pt blocks, hue stepping 47 degrees,
/// saturation 0.6, brightness 0.95 (UIColor's HSB), or a flat background.
class _Pattern extends CustomPainter {
  _Pattern(this.background);

  final String background;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect all = Offset.zero & size;
    switch (background) {
      case 'white':
        canvas.drawRect(all, Paint()..color = const Color(0xFFFFFFFF));
        return;
      case 'black':
        canvas.drawRect(all, Paint()..color = const Color(0xFF000000));
        return;
      case 'gray':
        canvas.drawRect(all, Paint()..color = const Color(0xFF808080));
        return;
      case 'vstripe8':
        canvas.drawRect(all, Paint()..color = const Color(0xFFFFFFFF));
        for (var x = 0.0; x < size.width; x += 8) {
          canvas.drawRect(
            Rect.fromLTWH(x, 0, 4, size.height),
            Paint()..color = const Color(0xFF000000),
          );
        }
        return;
      case final String g when g.startsWith('g'):
        final int v = ((double.tryParse(g.substring(1)) ?? 0.5) * 255).round();
        canvas.drawRect(all, Paint()..color = Color.fromARGB(255, v, v, v));
        return;
    }
    const double block = 44;
    var i = 0;
    for (var y = 0.0; y < size.height; y += block) {
      for (var x = 0.0; x < size.width; x += block) {
        canvas.drawRect(
          Rect.fromLTWH(x, y, block, block),
          Paint()
            ..color = HSVColor.fromAHSV(
              1,
              ((i * 47) % 360).toDouble(),
              0.6,
              0.95,
            ).toColor(),
        );
        i++;
      }
    }
  }

  @override
  bool shouldRepaint(_Pattern oldDelegate) =>
      oldDelegate.background != background;
}
