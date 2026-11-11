// Liquidum's side of the bars comparison: a GlassPage set up as the
// research catalog's native bars page (UINavigationController with a
// pattern page), from the same options in `<tmp>/comparison.txt`:
//
//   bars|barsroot [nav=<items>] [lead=<items>] [tool=<items>] [title=<t>]
//                 [large=1] [scroll=1] [offset=<pt>] [search=1]
//                 [bg=<background>]
//                 [style=dark]
//
// Items are "i:<symbol>", "t:<title>", "p:<title>" (prominent), "pi:<symbol>",
// "|" a fixed space, "~" a flexible space. `bars` is a pushed page (a back
// button, "Detail", and by default "..." and "+" and a toolbar); `barsroot`
// the root ("List", Edit, and a search field). Writes `<tmp>/ready.txt` 2s
// after the first frame.

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
      : <String>['bars'];
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
  runApp(BarsComparison(root: config.first == 'barsroot', options: options));
}

const Map<String, IconData> _symbols = <String, IconData>{
  'plus': CupertinoIcons.add,
  'ellipsis': CupertinoIcons.ellipsis,
  'trash': CupertinoIcons.trash,
  'square.and.arrow.up': CupertinoIcons.share,
  'folder': CupertinoIcons.folder,
  'sidebar.left': CupertinoIcons.sidebar_left,
  'checkmark': CupertinoIcons.checkmark,
};

List<GlassBarItem> _items(String spec) => <GlassBarItem>[
  for (final String part in spec.split(','))
    switch (part) {
      '|' || '~' => const GlassBarItem.space(),
      _ when part.startsWith('t:') => GlassBarItem(
        label: part.substring(2).replaceAll('_', ' '),
        onPressed: () {},
      ),
      _ when part.startsWith('p:') => GlassBarItem(
        label: part.substring(2).replaceAll('_', ' '),
        prominent: true,
        onPressed: () {},
      ),
      _ when part.startsWith('pi:') => GlassBarItem(
        icon: _symbols[part.substring(3)] ?? CupertinoIcons.circle,
        prominent: true,
        onPressed: () {},
      ),
      _ => GlassBarItem(
        icon: _symbols[part.replaceFirst('i:', '')] ?? CupertinoIcons.circle,
        onPressed: () {},
      ),
    },
];

class BarsComparison extends StatefulWidget {
  const BarsComparison({super.key, required this.root, required this.options});

  final bool root;
  final Map<String, String> options;

  @override
  State<BarsComparison> createState() => _BarsComparisonState();
}

class _BarsComparisonState extends State<BarsComparison> {
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, String> o = widget.options;
    final bool root = widget.root;
    final bool configured =
        o.containsKey('nav') || o.containsKey('lead') || o.containsKey('tool');
    final String title =
        o['title']?.replaceAll('_', ' ') ?? (root ? 'List' : 'Detail');
    final bool dark = o['style'] == 'dark';
    final List<GlassBarItem> actions = configured
        ? (o.containsKey('nav') ? _items(o['nav']!) : const <GlassBarItem>[])
        : root
        ? <GlassBarItem>[GlassBarItem(label: 'Edit', onPressed: () {})]
        : _items('i:ellipsis,i:plus');
    final List<GlassBarItem> toolbar = configured
        ? (o.containsKey('tool') ? _items(o['tool']!) : const <GlassBarItem>[])
        : root
        ? const <GlassBarItem>[]
        : _items('i:trash,~,i:square.and.arrow.up,~,p:Done');
    final bool search = configured ? o.containsKey('search') : root;
    final Widget pattern = CustomPaint(
      painter: _Pattern(o['bg'] ?? 'blocks'),
      size: Size.infinite,
    );
    final Widget content = o.containsKey('scroll')
        ? ListView(
            controller: ScrollController(
              initialScrollOffset: double.tryParse(o['offset'] ?? '') ?? 0,
            ),
            children: <Widget>[
              SizedBox(
                height: 3000,
                child: CustomPaint(painter: _Pattern(o['bg'] ?? 'blocks')),
              ),
            ],
          )
        : pattern;
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
      home: GlassPage(
        title: title,
        largeTitle: o.containsKey('large'),
        onBack: root ? null : () {},
        leading: o.containsKey('lead')
            ? _items(o['lead']!)
            : const <GlassBarItem>[],
        actions: actions,
        toolbar: search ? const <GlassBarItem>[] : toolbar,
        searchController: search ? _search : null,
        backgroundColor: dark
            ? const Color(0xFF000000)
            : const Color(0xFFFFFFFF),
        child: content,
      ),
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
