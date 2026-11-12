import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquidum/liquidum.dart';

// The places and sizes measured on UIKit's context menus (iOS 26.5,
// iPhone 17 Pro Max): a 140pt tile at (40, 280) lifts to 161pt about its
// center with its menu 20pt below; at (260, 640) the menu goes above, its
// right edge on the tile's; a 251.67 x 44 label at (20, 450) lifts 26pt
// longer, kept 20pt from the screen's side.
void main() {
  late List<String> chosen;

  List<GlassMenuItem> items() => <GlassMenuItem>[
    GlassMenuItem(label: 'Copy', onPressed: () => chosen.add('copy')),
    GlassMenuItem(label: 'Share', onPressed: () => chosen.add('share')),
    const GlassMenuItem.divider(),
    GlassMenuItem(
      label: 'Delete',
      destructive: true,
      onPressed: () => chosen.add('delete'),
    ),
  ];

  Future<void> show(
    WidgetTester tester,
    Rect box, {
    VoidCallback? onTap,
  }) async {
    tester.view.physicalSize = const Size(440, 956);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 62, bottom: 34);
    addTearDown(tester.view.reset);
    chosen = <String>[];
    await tester.pumpWidget(
      CupertinoApp(
        home: Stack(
          children: <Widget>[
            Positioned.fromRect(
              rect: box,
              child: GlassContextMenu(
                items: items(),
                child: GestureDetector(
                  onTap: onTap,
                  child: const ColoredBox(
                    key: ValueKey<String>('view'),
                    color: Color(0xFF0088FF),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // The view as drawn on top (the lifted copy in the overlay).
  Rect view(WidgetTester tester) =>
      tester.getRect(find.byKey(const ValueKey<String>('view')).last);

  Rect menu(WidgetTester tester) {
    final RenderBox glass = tester.renderObject(
      find.ancestor(of: find.text('Copy'), matching: find.byType(Glass)).first,
    );
    return glass.localToGlobal(Offset.zero) & glass.size;
  }

  Future<void> frames(WidgetTester tester, double seconds) async {
    for (var i = 0; i < (seconds * 60).round(); i++) {
      await tester.pump(const Duration(microseconds: 16667));
    }
  }

  void expectRect(Rect actual, Rect expected) {
    expect(actual.left, closeTo(expected.left, 0.6));
    expect(actual.top, closeTo(expected.top, 0.6));
    expect(actual.width, closeTo(expected.width, 0.6));
    expect(actual.height, closeTo(expected.height, 0.6));
  }

  testWidgets('a long press lifts the view and opens the menu below it', (
    WidgetTester tester,
  ) async {
    await show(tester, const Rect.fromLTWH(40, 280, 140, 140));
    final TestGesture finger = await tester.startGesture(
      const Offset(110, 350),
    );
    // Resting: the view grows about its center (UIKit: 152.4 at 0.74s).
    await frames(tester, 0.74);
    final Rect pressed = view(tester);
    expect(pressed.center.dx, closeTo(110, 0.5));
    expect(pressed.width, closeTo(152.4, 1.5));
    expect(find.text('Copy'), findsNothing);
    // At 0.8s the menu opens; the view lifts to 1.15.
    await frames(tester, 1.2);
    expectRect(view(tester), const Rect.fromLTWH(29.5, 269.5, 161, 161));
    expectRect(menu(tester), const Rect.fromLTWH(29.5, 450.5, 250, 167));
    // Lifting the finger where it rested leaves the menu open.
    await finger.up();
    await tester.pumpAndSettle();
    expect(find.text('Copy'), findsOneWidget);
    await tester.tap(find.text('Share'));
    await tester.pumpAndSettle();
    expect(chosen, <String>['share']);
    expect(find.text('Copy'), findsNothing);
    // Back in place: only the view itself.
    expect(find.byKey(const ValueKey<String>('view')), findsOneWidget);
  });

  testWidgets('near the bottom the menu goes above, right-aligned', (
    WidgetTester tester,
  ) async {
    await show(tester, const Rect.fromLTWH(260, 640, 140, 140));
    final TestGesture finger = await tester.startGesture(
      const Offset(330, 710),
    );
    await frames(tester, 2);
    expectRect(view(tester), const Rect.fromLTWH(249.5, 629.5, 161, 161));
    expectRect(menu(tester), const Rect.fromLTWH(160.5, 442.5, 250, 167));
    await finger.up();
    // A tap outside closes it.
    await tester.tapAt(const Offset(60, 140));
    await tester.pumpAndSettle();
    expect(find.text('Copy'), findsNothing);
    expect(chosen, isEmpty);
  });

  testWidgets('a wide view lifts 26pt longer, 20pt from the side', (
    WidgetTester tester,
  ) async {
    await show(tester, const Rect.fromLTWH(20, 450, 251.67, 44));
    final TestGesture finger = await tester.startGesture(
      const Offset(140, 472),
    );
    await frames(tester, 2);
    // UIKit: 277.67 x 48.67 at (20, 447.67); its menu at (20, 516.33).
    final Rect lifted = view(tester);
    expect(lifted.left, closeTo(20, 0.5));
    expect(lifted.width, closeTo(277.67, 0.5));
    expect(lifted.center.dy, closeTo(472, 0.5));
    final Rect m = menu(tester);
    expect(m.left, closeTo(20, 0.5));
    expect(m.top, closeTo(lifted.bottom + 20, 0.5));
    await finger.up();
    await tester.tapAt(const Offset(400, 140));
    await tester.pumpAndSettle();
    expect(find.text('Copy'), findsNothing);
  });

  testWidgets('a drag from the view onto a row chooses it', (
    WidgetTester tester,
  ) async {
    await show(tester, const Rect.fromLTWH(40, 280, 140, 140));
    final TestGesture finger = await tester.startGesture(
      const Offset(110, 350),
    );
    await frames(tester, 1.6);
    // Delete's row: 10 + 42 + 42 + 21 into the menu at (29.5, 450.5).
    await finger.moveTo(const Offset(120, 400));
    await frames(tester, 0.1);
    await finger.moveTo(const Offset(120, 450.5 + 115 + 21));
    await frames(tester, 0.1);
    await finger.up();
    await tester.pumpAndSettle();
    expect(chosen, <String>['delete']);
    expect(find.text('Copy'), findsNothing);
  });

  testWidgets('a short tap is the view\'s own; moving away cancels', (
    WidgetTester tester,
  ) async {
    var taps = 0;
    await show(
      tester,
      const Rect.fromLTWH(40, 280, 140, 140),
      onTap: () => taps++,
    );
    await tester.tapAt(const Offset(110, 350));
    await tester.pumpAndSettle();
    expect(taps, 1);
    expect(find.text('Copy'), findsNothing);

    // Resting long enough to grow, then sliding away: no menu, and the
    // view shrinks back into place.
    final TestGesture finger = await tester.startGesture(
      const Offset(110, 350),
    );
    await frames(tester, 0.5);
    expect(find.byKey(const ValueKey<String>('view')), findsWidgets);
    await finger.moveTo(const Offset(110, 420));
    await frames(tester, 1);
    await finger.up();
    await tester.pumpAndSettle();
    expect(find.text('Copy'), findsNothing);
    expect(find.byKey(const ValueKey<String>('view')), findsOneWidget);
    expect(taps, 1);
  });
}
