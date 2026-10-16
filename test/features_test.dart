import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquidum/liquidum.dart';
import 'package:liquidum/liquidum_debug.dart';
import 'package:liquidum/src/tab_bar/minimize.dart';
import 'package:liquidum/src/tab_bar/style.dart';

/// A long list, to scroll under the bar.
class Rows extends StatelessWidget {
  const Rows(this.name, {super.key});

  final String name;

  @override
  Widget build(BuildContext context) => ListView.builder(
    itemCount: 100,
    itemExtent: 44,
    itemBuilder: (BuildContext context, int i) => Text('$name $i'),
  );
}

void main() {
  setUp(() {});

  Widget app({Widget? accessory, bool minimize = false, bool search = true}) =>
      CupertinoApp(
        home: GlassTabScaffold(
          accessory: accessory,
          minimizeOnScroll: minimize,
          tabs: <GlassTab>[
            const GlassTab(
              icon: CupertinoIcons.house,
              label: 'Home',
              page: Rows('home'),
            ),
            const GlassTab(
              icon: CupertinoIcons.bell,
              label: 'Alerts',
              page: Rows('alerts'),
            ),
            if (search) const GlassTab.search(page: Rows('search')),
          ],
        ),
      );

  testWidgets('the search tab is a circle of its own at the trailing end', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1320, 2868);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    // The bar spans the margins: the platter hugs its two tabs at the
    // leading end, the circle sits at the trailing end.
    expect(tester.getRect(find.byType(GlassTabBar)).width, 398);
    await tester.tap(find.bySemanticsLabel('Search'));
    await tester.pumpAndSettle();
    expect(find.text('search 0'), findsOneWidget);
    expect(find.text('home 0'), findsNothing);
  });

  testWidgets('the accessory floats above the bar, and pages clear it', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1320, 2868);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(accessory: const Text('Now Playing')));
    expect(find.text('Now Playing'), findsOneWidget);
    expect(
      tester.getRect(find.byType(GlassTabBar)).height,
      62 + GlassTabBar.accessoryHeight + GlassTabBar.accessoryGap,
    );
    final BuildContext page = tester.element(find.byType(ListView).first);
    expect(MediaQuery.paddingOf(page).bottom, 21 + 62 + 48 + 8);
    // Its content takes taps.
    var tapped = false;
    await tester.pumpWidget(
      app(
        accessory: GestureDetector(
          onTap: () => tapped = true,
          child: const Text('Now Playing'),
        ),
      ),
    );
    await tester.tap(find.text('Now Playing'));
    expect(tapped, isTrue);
  });

  testWidgets('scrolling down minimizes the bar, up expands it', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(app(minimize: true));
    GlassTabBar bar() => tester.widget<GlassTabBar>(find.byType(GlassTabBar));
    expect(bar().minimized, isFalse);
    await tester.drag(find.text('home 3'), const Offset(0, -200));
    await tester.pump();
    expect(bar().minimized, isTrue);
    await tester.drag(find.text('home 8'), const Offset(0, 100));
    await tester.pump();
    expect(bar().minimized, isFalse);
  });

  testWidgets('the search tab opens into a field, as UIKit with a controller', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1320, 2868);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    final queries = <String>[];
    await tester.pumpWidget(
      CupertinoApp(
        home: GlassTabScaffold(
          tabs: <GlassTab>[
            const GlassTab(
              icon: CupertinoIcons.house,
              label: 'Home',
              page: Rows('home'),
            ),
            const GlassTab(
              icon: CupertinoIcons.bell,
              label: 'Alerts',
              page: Rows('alerts'),
            ),
            GlassTab.search(
              controller: controller,
              onChanged: queries.add,
              page: const Rows('search'),
            ),
          ],
        ),
      ),
    );
    await tester.tap(find.bySemanticsLabel('Search'));
    await tester.pumpAndSettle();
    expect(find.text('search 0'), findsOneWidget);
    // The field takes text.
    await tester.tap(find.byType(EditableText));
    await tester.pump();
    await tester.enterText(find.byType(EditableText), 'abc');
    expect(controller.text, 'abc');
    expect(queries.last, 'abc');
    // Its close button clears it and ends the editing.
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Close'));
    await tester.pumpAndSettle();
    expect(controller.text, isEmpty);
    // The collapsed tabs' circle goes back to the last tab.
    await tester.tap(find.bySemanticsLabel('Home').last);
    await tester.pumpAndSettle();
    expect(find.text('home 0'), findsOneWidget);
  });

  test('the minimized bar moves with UIKit springs, the accessory later', () {
    final m = GlassTabBarMinimize()..set(true, 0);
    m.tick(0.05);
    expect(m.size.value, greaterThan(0));
    // The platter's shape and the crossfade start 0.09s after the
    // selection, the accessory 0.1s and 0.15s after.
    expect(m.platterWidth.value, 0);
    expect(m.fade.value, 0);
    expect(m.accessorySpan.value, 0);
    expect(m.accessoryDrop.value, 0);
    for (var t = 0.1; t < 2; t += 1 / 60) {
      m.tick(t);
    }
    expect(m.size.value, moreOrLessEquals(1, epsilon: 1e-3));
    expect(m.accessoryDrop.value, moreOrLessEquals(1, epsilon: 1e-3));
    expect(m.isSettled, isTrue);
  });

  test('beside a search tab, the tabs fill from three on, as UIKit', () {
    expect(GlassTabBarPhysics.naturalWidth(2, 30, search: true), 188);
    expect(GlassTabBarPhysics.naturalWidth(3, 30, search: true), isNull);
    final p = GlassTabBarPhysics(count: 3, selectedIndex: 0)
      ..layout(const Size(328, 62), 3, search: true);
    expect(p.pillWidth, moreOrLessEquals(113.33, epsilon: 0.01));
    p.layout(const Size(328, 62), 4, search: true);
    expect(p.pillWidth, 85.5);
  });

  test('Increase Contrast darkens a selected color as UIKit does', () {
    Color c(int argb) =>
        GlassTabBarStyle.resolve(Color(argb), dark: false, contrast: true);
    // UIKit's (iOS 26.5): red (191, 35, 26), green (29, 147, 59).
    final Color red = c(0xFFFF3B30), green = c(0xFF34C759);
    expect((red.r * 255 - 191).abs(), lessThan(3));
    expect((red.g * 255 - 35).abs(), lessThan(3));
    expect((green.g * 255 - 147).abs(), lessThan(3));
    expect(
      GlassTabBarStyle.resolve(
        GlassTabBarStyle.systemBlue,
        dark: false,
        contrast: true,
      ),
      const Color(0xFF1E6EF4),
    );
  });
}
