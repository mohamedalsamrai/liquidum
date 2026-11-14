// Liquidum's side of the menus comparison: glass buttons with menus laid out
// as the research catalog's native menus page, from the same options in
// `<tmp>/comparison.txt`:
//
//   menus|menusnav [items=<list>] [bg=<background>] [style=dark]
//
// Items are "Title", "Title/symbol", "Title/symbol/d" (destructive),
// "Title/symbol/c" (checked), ">Title" (a submenu of three), "-" a divider.
// Buttons: "Menu" at 20,200; an ellipsis at 200,200; a plus at the right
// edge; "Bottom" at 20,820; a prominent button at the bottom right. Context
// menus (the same items): a white label at 20,450, a clear label at
// 300,530, a blue tile at 40,280 and an orange one at 260,640 (140pt).
// `menusnav`: three GlassPages pushed (First, Second, Third), the last with
// an ellipsis item whose menu is the items (the back button's long press
// lists the pages under it). `editmenu [on=box] [items=] [at=x,y]
// [show=<s,...>] [hide=<s,...>]`: the catalog's edit menu page, a text
// view at 20,160 (400 x 120, 22pt) with "brown" selected and a blue box at
// 120,420 (200 x 120); GlassEditMenu shows at the given seconds (on the
// text's selection, or on=box at the point at=x,y in the box). Writes
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
        : config.first == 'editmenu'
        ? EditMenuComparison(options: options)
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
              Positioned(
                left: 20,
                top: 450,
                width: 251.67,
                height: 44,
                child: GlassContextMenu(
                  items: items,
                  child: const ColoredBox(
                    color: Color(0xFFFFFFFF),
                    child: Center(
                      child: _Text('Long-press for a context menu'),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 300,
                top: 530,
                width: 110,
                height: 44,
                child: GlassContextMenu(
                  items: items,
                  child: const Center(child: _Text('Clear')),
                ),
              ),
              for (final (double x, double y, Color color)
                  in <(double, double, Color)>[
                    (40, 280, const Color(0xFF0088FF)),
                    (260, 640, const Color(0xFFFF8D28)),
                  ])
                Positioned(
                  left: x,
                  top: y,
                  width: 140,
                  height: 140,
                  child: GlassContextMenu(items: items, child: _Tile(color)),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Text extends StatelessWidget {
  const _Text(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      fontSize: 17,
      color: Color(0xFF000000),
      decoration: TextDecoration.none,
    ),
  );
}

// The catalog's tile: 140pt, continuous corners of 16pt, "Tile" in white.
class _Tile extends StatelessWidget {
  const _Tile(this.color);

  final Color color;

  @override
  Widget build(BuildContext context) => ClipRSuperellipse(
    borderRadius: const BorderRadius.all(Radius.circular(16)),
    child: ColoredBox(
      color: color,
      child: const Center(
        child: Text(
          'Tile',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            color: Color(0xFFFFFFFF),
            decoration: TextDecoration.none,
          ),
        ),
      ),
    ),
  );
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

/// The catalog's edit menu page (see the top of the file).
class EditMenuComparison extends StatefulWidget {
  const EditMenuComparison({super.key, required this.options});

  final Map<String, String> options;

  @override
  State<EditMenuComparison> createState() => _EditMenuComparisonState();
}

class _EditMenuComparisonState extends State<EditMenuComparison> {
  final TextEditingController _text = TextEditingController(
    text: 'The quick brown fox jumps over the lazy dog.',
  );
  final FocusNode _focus = FocusNode();
  final GlobalKey<EditableTextState> _field = GlobalKey<EditableTextState>();
  final GlobalKey _box = GlobalKey();
  final ContextMenuController _controller = ContextMenuController();
  final List<Timer> _timers = <Timer>[];

  bool get _onBox => widget.options['on'] == 'box';

  List<double> _times(String key) => <double>[
    for (final String t in (widget.options[key] ?? '').split(','))
      if (double.tryParse(t) != null) double.parse(t),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_onBox) {
        _focus.requestFocus();
        // Selected as a double tap selects a word (a selection set in code
        // gets no handles and no menu).
        _timers.add(
          Timer(const Duration(milliseconds: 300), () {
            final EditableTextState? field = _field.currentState;
            field?.userUpdateTextEditingValue(
              _text.value.copyWith(
                selection: const TextSelection(
                  baseOffset: 10,
                  extentOffset: 15,
                ),
              ),
              SelectionChangedCause.doubleTap,
            );
            field?.hideToolbar();
          }),
        );
      }
      for (final double t in _times('show')) {
        _timers.add(Timer(Duration(milliseconds: (t * 1000).round()), _show));
      }
      for (final double t in _times('hide')) {
        _timers.add(Timer(Duration(milliseconds: (t * 1000).round()), _hide));
      }
    });
  }

  void _show() {
    if (!_onBox) {
      _field.currentState?.showToolbar();
      return;
    }
    final RenderBox box = _box.currentContext!.findRenderObject()! as RenderBox;
    final List<double> at = (widget.options['at'] ?? '100,0')
        .split(',')
        .map(double.parse)
        .toList();
    _controller.show(
      context: _box.currentContext!,
      contextMenuBuilder: (BuildContext context) => GlassEditMenu(
        anchors: TextSelectionToolbarAnchors(
          primaryAnchor: box.localToGlobal(Offset(at[0], at[1])),
        ),
        items: _menu(widget.options['items'] ?? 'Copy,Paste,Delete'),
      ),
    );
  }

  void _hide() {
    if (_onBox) {
      _controller.remove();
    } else {
      _field.currentState?.hideToolbar();
    }
  }

  @override
  void dispose() {
    for (final Timer t in _timers) {
      t.cancel();
    }
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool dark = widget.options['style'] == 'dark';
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
      // The page is a backdrop: small glass over it (the menu) adapts to
      // it, as over a GlassPage.
      home: GlassBackdrop(
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: CustomPaint(
                painter: _Pattern(widget.options['bg'] ?? 'blocks'),
              ),
            ),
            Positioned(
              left: 20,
              top: 160,
              width: 400,
              height: 120,
              child: Container(
                color: dark ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
                padding: const EdgeInsets.fromLTRB(5, 8, 5, 8),
                child: EditableText(
                  key: _field,
                  controller: _text,
                  focusNode: _focus,
                  maxLines: null,
                  // UITextView's insets: 8pt down, 5pt in.
                  style: TextStyle(
                    fontSize: 22,
                    color: dark
                        ? const Color(0xFFFFFFFF)
                        : const Color(0xFF000000),
                  ),
                  cursorColor: const Color(0xFF146FE1),
                  backgroundCursorColor: const Color(0xFF8E8E93),
                  selectionColor: const Color(0x33146FE1),
                  selectionControls: cupertinoTextSelectionHandleControls,
                  contextMenuBuilder: GlassEditMenu.builder,
                  showSelectionHandles: true,
                  rendererIgnoresPointer: false,
                ),
              ),
            ),
            Positioned(
              left: 120,
              top: 420,
              width: 200,
              height: 120,
              child: ColoredBox(key: _box, color: const Color(0xFF0088FF)),
            ),
          ],
        ),
      ),
    );
  }
}
