import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquidum/liquidum.dart';

// UIKit's navigation bar between two pages (iOS 26.5, iPhone 17 Pro Max):
// the bar stays while the pages slide under it; a platter whose items
// change morphs (a "+" into "... share": at 0.1s 370.3,58.0 53.9x52.0, at
// 0.15s 351.9,57.0 75.1x54.1); a platter on one page only melts into its
// neighbor (a 22pt circle at its center) or grows out of it; the same
// platters stay still.
void main() {
  late GlobalKey<NavigatorState> navigator;

  Future<void> show(WidgetTester tester, List<GlassBarItem> rootItems) async {
    tester.view.physicalSize = const Size(440, 956);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 62, bottom: 34);
    addTearDown(tester.view.reset);
    navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      CupertinoApp(
        navigatorKey: navigator,
        home: GlassPage(
          title: 'List',
          actions: rootItems,
          child: const SizedBox.expand(),
        ),
      ),
    );
  }

  void push(List<GlassBarItem> items) {
    navigator.currentState!.push(
      CupertinoPageRoute<void>(
        builder: (BuildContext context) => GlassPage(
          title: 'Detail',
          onBack: () => Navigator.pop(context),
          actions: items,
          child: const SizedBox.expand(),
        ),
      ),
    );
  }

  // The glass of the bar between the two pages, on the screen, by left.
  List<Rect> morphing(WidgetTester tester) {
    final Finder layer = find.byWidgetPredicate(
      (Widget w) => w.runtimeType.toString() == '_ScreenFixed',
    );
    return <Rect>[
      for (final Element e
          in find
              .descendant(of: layer, matching: find.byType(Glass))
              .evaluate())
        tester.getRect(find.byElementPredicate((Element x) => x == e)),
    ]..sort((Rect a, Rect b) => a.left.compareTo(b.left));
  }

  Future<void> frames(WidgetTester tester, int n) async {
    for (var i = 0; i < n; i++) {
      await tester.pump(const Duration(microseconds: 16667));
    }
  }

  void expectRect(Rect actual, Rect expected, [double within = 1.5]) {
    expect(actual.left, closeTo(expected.left, within));
    expect(actual.top, closeTo(expected.top, within));
    expect(actual.width, closeTo(expected.width, within));
    expect(actual.height, closeTo(expected.height, within));
  }

  List<GlassBarItem> icons(List<IconData> icons) => <GlassBarItem>[
    for (final IconData i in icons) GlassBarItem(icon: i, onPressed: () {}),
  ];

  testWidgets('a push keeps the bar and morphs its platter as UIKit\'s', (
    WidgetTester tester,
  ) async {
    await show(tester, icons(<IconData>[CupertinoIcons.add]));
    push(icons(<IconData>[CupertinoIcons.ellipsis, CupertinoIcons.share]));
    await frames(tester, 6);
    // 0.1s in: the back button materializing at its place, the "+" swelling
    // into the wider platter.
    List<Rect> glass = morphing(tester);
    expectRect(glass.first, const Rect.fromLTWH(20, 62, 44, 44), 0.1);
    expectRect(glass.last, const Rect.fromLTWH(370.3, 58.0, 53.9, 52.0));
    await frames(tester, 3);
    glass = morphing(tester);
    expectRect(glass.last, const Rect.fromLTWH(351.9, 57.0, 75.1, 54.1), 2);
    // Fixed on the screen while the page slides (swelling a little past
    // its trailing end, as UIKit's, to 425): it does not ride the page.
    for (var i = 0; i < 6; i++) {
      await frames(tester, 2);
      expect(morphing(tester).last.right, inInclusiveRange(419, 430));
    }
    await tester.pumpAndSettle();
    expect(morphing(tester), isEmpty);
    expect(find.text('Detail'), findsOneWidget);

    // Back: the platter shrinks back to the "+", the back button goes.
    navigator.currentState!.pop();
    await frames(tester, 5);
    glass = morphing(tester);
    expect(glass.last.width, greaterThan(100));
    await tester.pumpAndSettle();
    expect(morphing(tester), isEmpty);
    expect(find.text('Detail'), findsNothing);
  });

  testWidgets('a platter on one page only melts into its neighbor', (
    WidgetTester tester,
  ) async {
    await show(tester, <GlassBarItem>[
      GlassBarItem(label: 'Edit', onPressed: () {}),
      const GlassBarItem.space(),
      GlassBarItem(icon: CupertinoIcons.add, onPressed: () {}),
    ]);
    push(icons(<IconData>[CupertinoIcons.ellipsis]));
    await frames(tester, 36);
    // "Edit" has shrunk to a 22pt circle at the "+"'s center (UIKit:
    // 387,73 22x22), inside the trailing platter.
    final List<Rect> glass = morphing(tester);
    final Rect melted = glass.firstWhere(
      (Rect r) => r.width < 30 && r.left > 300,
    );
    expectRect(melted, const Rect.fromLTWH(387, 73, 22, 22), 1);
    await tester.pumpAndSettle();

    // Back: it grows out of the "+" again, from 8.8pt after 0.21s.
    navigator.currentState!.pop();
    await frames(tester, 6);
    final Rect seed = morphing(tester).firstWhere((Rect r) => r.width < 10);
    expectRect(seed, const Rect.fromLTWH(393.6, 79.6, 8.8, 8.8), 0.5);
    await tester.pumpAndSettle();
    expect(morphing(tester), isEmpty);
    expect(find.bySemanticsLabel('Edit'), findsOneWidget);
  });

  testWidgets('the same platters stay still between two pages', (
    WidgetTester tester,
  ) async {
    await show(tester, icons(<IconData>[CupertinoIcons.ellipsis]));
    push(icons(<IconData>[CupertinoIcons.ellipsis]));
    await tester.pumpAndSettle();
    push(icons(<IconData>[CupertinoIcons.ellipsis]));
    for (var i = 0; i < 20; i++) {
      await frames(tester, 1);
      for (final Rect r in morphing(tester)) {
        expect(r.size, const Size(44, 44));
      }
    }
    await tester.pumpAndSettle();
  });

  testWidgets('a finger drives the pop', (WidgetTester tester) async {
    await show(tester, icons(<IconData>[CupertinoIcons.add]));
    push(icons(<IconData>[CupertinoIcons.ellipsis, CupertinoIcons.share]));
    await tester.pumpAndSettle();
    // From the screen's leading edge, halfway across.
    final TestGesture finger = await tester.startGesture(const Offset(5, 400));
    for (var i = 0; i < 10; i++) {
      await finger.moveBy(const Offset(22, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    final Rect half = morphing(tester).last;
    expect(half.width, greaterThan(50));
    expect(half.width, lessThan(95));
    expect(half.right, closeTo(420, 1));
    // Let go past halfway: the pop goes on.
    await finger.moveBy(const Offset(60, 0));
    await finger.up();
    await tester.pumpAndSettle();
    expect(find.text('Detail'), findsNothing);
    expect(morphing(tester), isEmpty);
  });

  testWidgets('a pop given up puts the bar back', (WidgetTester tester) async {
    await show(tester, icons(<IconData>[CupertinoIcons.add]));
    push(icons(<IconData>[CupertinoIcons.ellipsis, CupertinoIcons.share]));
    await tester.pumpAndSettle();
    final TestGesture finger = await tester.startGesture(const Offset(5, 400));
    for (var i = 0; i < 4; i++) {
      await finger.moveBy(const Offset(20, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(morphing(tester), isNotEmpty);
    // Let go a quarter of the way, slowly: the page slides back.
    await tester.pump(const Duration(milliseconds: 300));
    await finger.up();
    await tester.pumpAndSettle();
    expect(find.text('Detail'), findsOneWidget);
    expect(morphing(tester), isEmpty);
    expect(find.bySemanticsLabel('Back'), findsOneWidget);
  });

  testWidgets('a toolbar on one page only stays put as it comes and goes', (
    WidgetTester tester,
  ) async {
    await show(tester, icons(<IconData>[CupertinoIcons.add]));
    navigator.currentState!.push(
      CupertinoPageRoute<void>(
        builder: (BuildContext context) => GlassPage(
          title: 'Detail',
          onBack: () => Navigator.pop(context),
          toolbar: <GlassBarItem>[
            GlassBarItem(
              icon: CupertinoIcons.trash,
              semanticLabel: 'Trash',
              onPressed: () {},
            ),
          ],
          child: const SizedBox.expand(),
        ),
      ),
    );
    await frames(tester, 2);
    final Rect start = tester.getRect(find.bySemanticsLabel('Trash'));
    // Fixed on the screen while its page slides in.
    for (var i = 0; i < 8; i++) {
      await frames(tester, 2);
      final Rect now = tester.getRect(find.bySemanticsLabel('Trash'));
      expect(now.left, closeTo(start.left, 0.5));
    }
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.bySemanticsLabel('Trash')).left,
      closeTo(start.left, 0.5),
    );
    navigator.currentState!.pop();
    await frames(tester, 6);
    expect(
      tester.getRect(find.bySemanticsLabel('Trash')).left,
      closeTo(start.left, 0.5),
    );
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Trash'), findsNothing);
  });
}
