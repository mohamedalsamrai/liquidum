import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquidum/liquidum.dart';

/// A page with a counter, to see that its state is kept.
class Counter extends StatefulWidget {
  const Counter(this.name, {super.key});

  final String name;

  @override
  State<Counter> createState() => _CounterState();
}

class _CounterState extends State<Counter> {
  int count = 0;

  @override
  Widget build(BuildContext context) => Center(
    child: GestureDetector(
      onTap: () => setState(() => count++),
      child: Text('${widget.name} $count'),
    ),
  );
}

Widget app({
  TextDirection direction = TextDirection.ltr,
  ValueChanged<int>? onTabChanged,
}) => CupertinoApp(
  home: Directionality(
    textDirection: direction,
    child: GlassTabScaffold(
      onTabChanged: onTabChanged,
      tabs: const <GlassTab>[
        GlassTab(
          icon: CupertinoIcons.house,
          label: 'Home',
          page: Counter('home'),
        ),
        GlassTab(
          icon: CupertinoIcons.bell,
          label: 'Alerts',
          badge: '3',
          page: Counter('alerts'),
        ),
        GlassTab(
          icon: CupertinoIcons.person,
          label: 'Profile',
          page: Counter('profile'),
        ),
      ],
    ),
  ),
);

/// Taps the bar where [label]'s tab is.
Future<void> tapTab(WidgetTester tester, String label) async {
  await tester.tap(find.text(label).first, warnIfMissed: false);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('tabs switch and keep their pages', (WidgetTester tester) async {
    final changes = <int>[];
    await tester.pumpWidget(app(onTabChanged: changes.add));
    expect(find.text('home 0'), findsOneWidget);
    // Pages are built when first shown.
    expect(find.text('alerts 0', skipOffstage: false), findsNothing);

    await tester.tap(find.text('home 0'));
    await tester.pump();
    await tapTab(tester, 'Alerts');
    expect(changes, <int>[1]);
    expect(find.text('alerts 0'), findsOneWidget);
    expect(find.text('home 1'), findsNothing);

    await tapTab(tester, 'Home');
    expect(find.text('home 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('badges show on their tab', (WidgetTester tester) async {
    await tester.pumpWidget(app());
    expect(find.text('3'), findsWidgets);
    expect(
      tester.getSemantics(find.bySemanticsLabel('Alerts')),
      matchesSemantics(
        label: 'Alerts',
        value: '3',
        isButton: true,
        hasTapAction: true,
        hasSelectedState: true,
      ),
    );
  });

  testWidgets('pushed pages stay in their tab; reselecting pops them', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(app());
    final BuildContext page = tester.element(find.text('home 0'));
    Navigator.of(page).push(
      PageRouteBuilder<void>(
        pageBuilder: (BuildContext context, _, _) =>
            const Center(child: Text('detail')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('detail'), findsOneWidget);
    // The bar is still there, over the pushed page.
    expect(find.byType(GlassTabBar), findsOneWidget);

    await tapTab(tester, 'Alerts');
    expect(find.text('detail'), findsNothing);
    await tapTab(tester, 'Home');
    expect(find.text('detail'), findsOneWidget);

    await tapTab(tester, 'Home');
    expect(find.text('detail'), findsNothing);
    expect(find.text('home 0'), findsOneWidget);
  });

  testWidgets('right to left, the first tab is on the right', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(app(direction: TextDirection.rtl));
    final double home = tester.getCenter(find.text('Home').first).dx;
    final double profile = tester.getCenter(find.text('Profile').first).dx;
    expect(home, greaterThan(profile));
    await tapTab(tester, 'Profile');
    expect(find.text('profile 0'), findsOneWidget);
  });

  testWidgets('switching from code, and the pages see the bar in padding', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(app());
    final BuildContext page = tester.element(find.text('home 0'));
    // 21pt margin and the 62pt bar.
    expect(MediaQuery.paddingOf(page).bottom, 83);
    GlassTabScaffold.of(page).index = 2;
    await tester.pumpAndSettle();
    expect(find.text('profile 0'), findsOneWidget);
  });

  testWidgets('decorated glass lays out and paints', (
    WidgetTester tester,
  ) async {
    const shadow = BoxShadow(color: Color(0x1A000000), blurRadius: 6);
    await tester.pumpWidget(
      const CupertinoApp(
        home: GlassTabScaffold(
          glass: GlassDecoration(
            color: Color(0xC21E1E1E),
            shadows: <BoxShadow>[shadow],
            innerShadows: <BoxShadow>[
              BoxShadow(color: Color(0x40000000), blurRadius: 13),
            ],
          ),
          indicator: GlassDecoration(
            gradient: LinearGradient(
              colors: <Color>[Color(0xFFD82789), Color(0xFF7257A8)],
            ),
            shadows: <BoxShadow>[shadow],
          ),
          lensColor: Color(0xB37257A8),
          tabs: <GlassTab>[
            GlassTab(
              icon: CupertinoIcons.house,
              label: 'Home',
              page: Counter('home'),
            ),
            GlassTab(
              icon: CupertinoIcons.bell,
              label: 'Alerts',
              page: Counter('alerts'),
            ),
          ],
        ),
      ),
    );
    await tapTab(tester, 'Alerts');
    expect(find.text('alerts 0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('a decoration takes a shorthand color only when it has none', () {
    const red = Color(0xFFFF0000);
    const blue = Color(0xFF0000FF);
    expect(const GlassDecoration().withColor(red).color, red);
    expect(const GlassDecoration(color: blue).withColor(red).color, blue);
    const gradient = LinearGradient(colors: <Color>[red, blue]);
    expect(
      const GlassDecoration(gradient: gradient).withColor(red).color,
      isNull,
    );
    expect(
      const GlassDecoration(shadows: <BoxShadow>[BoxShadow()]),
      const GlassDecoration(shadows: <BoxShadow>[BoxShadow()]),
    );
  });

  testWidgets('the bar keeps a custom margin, and the pages clear it', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1320, 2868);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    Widget scaffold(EdgeInsetsGeometry margin, TextDirection direction) =>
        CupertinoApp(
          home: Directionality(
            textDirection: direction,
            child: GlassTabScaffold(
              barMargin: margin,
              tabs: <GlassTab>[
                for (final String name in <String>['a', 'b', 'c', 'd'])
                  GlassTab(
                    icon: CupertinoIcons.house,
                    label: name,
                    page: Counter(name),
                  ),
              ],
            ),
          ),
        );
    await tester.pumpWidget(
      scaffold(const EdgeInsets.fromLTRB(10, 0, 30, 40), TextDirection.ltr),
    );
    expect(
      tester.getRect(find.byType(GlassTabBar)),
      const Rect.fromLTRB(10, 956 - 40 - 62, 440 - 30, 956 - 40),
    );
    expect(
      MediaQuery.paddingOf(tester.element(find.text('a 0'))).bottom,
      40 + 62,
    );
    // Start is the right in a right-to-left app.
    await tester.pumpWidget(
      scaffold(
        const EdgeInsetsDirectional.fromSTEB(10, 0, 30, 40),
        TextDirection.rtl,
      ),
    );
    final Rect bar = tester.getRect(find.byType(GlassTabBar));
    expect(bar.left, 30);
    expect(bar.right, 440 - 10);
  });

  testWidgets('padding inside the bar grows it around its tabs', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1320, 2868);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const CupertinoApp(
        home: GlassTabScaffold(
          barMargin: EdgeInsets.only(bottom: 30),
          barPadding: EdgeInsets.all(12),
          tabs: <GlassTab>[
            GlassTab(
              icon: CupertinoIcons.house,
              label: 'a',
              page: Counter('a'),
            ),
            GlassTab(icon: CupertinoIcons.bell, label: 'b', page: Counter('b')),
            GlassTab(icon: CupertinoIcons.star, label: 'c', page: Counter('c')),
          ],
        ),
      ),
    );
    final Rect bar = tester.getRect(find.byType(GlassTabBar));
    // Three 94pt tabs overlapping by 8pt, 12pt of padding each side.
    expect(bar.size, const Size(3 * 94 - 16 + 24, 54 + 24));
    expect(bar.center.dx, 220);
    expect(bar.bottom, 956 - 30);
    expect(
      MediaQuery.paddingOf(tester.element(find.text('a 0'))).bottom,
      30 + 54 + 24,
    );
    await tapTab(tester, 'c');
    expect(find.text('c 0'), findsOneWidget);
  });
}
