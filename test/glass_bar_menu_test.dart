import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquidum/liquidum.dart';

void main() {
  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(440, 956);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 62, bottom: 34);
    addTearDown(tester.view.reset);
  }

  Rect glassOf(WidgetTester tester, Finder text) {
    final RenderBox glass = tester.renderObject(
      find.ancestor(of: text, matching: find.byType(Glass)).first,
    );
    return glass.localToGlobal(Offset.zero) & glass.size;
  }

  testWidgets('a bar item opens its menu out of its glass', (
    WidgetTester tester,
  ) async {
    phone(tester);
    var chosen = '';
    await tester.pumpWidget(
      CupertinoApp(
        home: GlassPage(
          title: 'Third',
          actions: <GlassBarItem>[
            GlassBarItem(
              icon: CupertinoIcons.ellipsis,
              semanticLabel: 'More',
              menu: <GlassMenuItem>[
                GlassMenuItem(label: 'Copy', onPressed: () => chosen = 'copy'),
                GlassMenuItem(label: 'Share', onPressed: () {}),
              ],
            ),
          ],
          child: const SizedBox.expand(),
        ),
      ),
    );
    await tester.tap(find.bySemanticsLabel('More'));
    await tester.pumpAndSettle();
    // From the item's platter (a 44pt circle 20pt from the right, at the
    // bar's top): the menu's right edge and top on it, as UIKit's.
    final Rect menu = glassOf(tester, find.text('Copy'));
    expect(menu.right, closeTo(420, 0.5));
    expect(menu.top, closeTo(62, 0.5));
    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();
    expect(chosen, 'copy');
    expect(find.text('Copy'), findsNothing);
  });

  testWidgets('a long press on the back button lists the pages under it', (
    WidgetTester tester,
  ) async {
    phone(tester);
    final GlobalKey<NavigatorState> navigator = GlobalKey<NavigatorState>();
    Widget page(String title, {bool back = true}) => Builder(
      builder: (BuildContext context) => GlassPage(
        title: title,
        onBack: back ? () => Navigator.pop(context) : null,
        child: const SizedBox.expand(),
      ),
    );
    await tester.pumpWidget(
      CupertinoApp(navigatorKey: navigator, home: page('First', back: false)),
    );
    navigator.currentState!.push(
      CupertinoPageRoute<void>(builder: (_) => page('Second')),
    );
    await tester.pumpAndSettle();
    navigator.currentState!.push(
      CupertinoPageRoute<void>(builder: (_) => page('Third')),
    );
    await tester.pumpAndSettle();
    final Finder back = find.bySemanticsLabel('Back').last;
    final TestGesture finger = await tester.startGesture(
      tester.getCenter(back),
    );
    await tester.pump(const Duration(milliseconds: 700));
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    // Nearest first, from the back button's corner.
    expect(find.text('Second'), findsWidgets);
    final Offset second = tester.getCenter(find.text('Second').last);
    final Offset first = tester.getCenter(find.text('First').last);
    expect(second.dy, lessThan(first.dy));
    final Rect menu = glassOf(tester, find.text('First').last);
    expect(menu.left, closeTo(20, 0.5));
    expect(menu.top, closeTo(62, 0.5));
    // Lifting on a row goes back to that page.
    await finger.moveTo(first);
    await tester.pump();
    await finger.up();
    await tester.pumpAndSettle();
    expect(find.text('Third'), findsNothing);
    expect(find.text('Second'), findsNothing);
    expect(find.text('First'), findsOneWidget);
  });

  testWidgets('lifting in place after the long press chooses that row', (
    WidgetTester tester,
  ) async {
    phone(tester);
    final GlobalKey<NavigatorState> navigator = GlobalKey<NavigatorState>();
    Widget page(String title, {bool back = true}) => Builder(
      builder: (BuildContext context) => GlassPage(
        title: title,
        onBack: back ? () => Navigator.pop(context) : null,
        child: const SizedBox.expand(),
      ),
    );
    await tester.pumpWidget(
      CupertinoApp(navigatorKey: navigator, home: page('First', back: false)),
    );
    navigator.currentState!.push(
      CupertinoPageRoute<void>(builder: (_) => page('Second')),
    );
    await tester.pumpAndSettle();
    navigator.currentState!.push(
      CupertinoPageRoute<void>(builder: (_) => page('Third')),
    );
    await tester.pumpAndSettle();
    final TestGesture finger = await tester.startGesture(
      tester.getCenter(find.bySemanticsLabel('Back').last),
    );
    for (var i = 0; i < 80; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await finger.up();
    await tester.pumpAndSettle();
    // The back button is under the menu's first row: "Second".
    expect(find.text('Third'), findsNothing);
    expect(find.text('Second'), findsOneWidget);
  });
}
