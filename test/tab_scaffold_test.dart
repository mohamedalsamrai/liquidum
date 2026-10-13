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
}
