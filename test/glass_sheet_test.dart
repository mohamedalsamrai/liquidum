// ignore: deprecated_member_use
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquidum/liquidum.dart';

// UIKit's sheet (iOS 26.5, iPhone 17 Pro Max: 440 x 956, safe area 62 / 34).
// At its medium detent (0.56 of the 860pt the screen leaves) it is a panel
// of glass at 8, 451.08, 424 x 496.92 (scaled to keep 8pt off the sides and
// bottom); at its large one it is 0, 62, 440 x 894 and opaque.
void main() {
  Future<void> open(
    WidgetTester tester, {
    List<GlassSheetDetent> detents = const <GlassSheetDetent>[
      GlassSheetDetent.medium,
      GlassSheetDetent.large,
    ],
    List<Object?>? results,
  }) async {
    tester.view.physicalSize = const Size(1320, 2868);
    tester.view.devicePixelRatio = 3;
    tester.view.padding = const FakeViewPadding(top: 186, bottom: 102);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      CupertinoApp(
        home: Builder(
          builder: (BuildContext context) => Center(
            child: GestureDetector(
              onTap: () async {
                final Object? r = await showGlassSheet<Object>(
                  context: context,
                  detents: detents,
                  builder: (BuildContext context) => const Align(
                    alignment: Alignment.topLeft,
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('Sheet'),
                    ),
                  ),
                );
                results?.add(r);
              },
              child: const Text('Show'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();
  }

  Rect sheet(WidgetTester tester) => tester.getRect(find.byType(Glass));

  void expectRect(Rect r, Rect want) {
    expect(r.left, closeTo(want.left, 0.05));
    expect(r.top, closeTo(want.top, 0.05));
    expect(r.width, closeTo(want.width, 0.05));
    expect(r.height, closeTo(want.height, 0.05));
  }

  testWidgets('the medium detent, as UIKit\'s', (WidgetTester tester) async {
    await open(tester);
    expectRect(sheet(tester), const Rect.fromLTWH(8, 451.08, 424, 496.92));
    // The content is scaled with the sheet: 24pt in is 23.13pt.
    final Rect label = tester.getRect(find.text('Sheet'));
    expect(label.left - 8, closeTo(24 * 424 / 440, 0.05));
  });

  testWidgets('dragged up it fills the screen and turns opaque', (
    WidgetTester tester,
  ) async {
    await open(tester);
    final TestGesture g = await tester.startGesture(const Offset(220, 600));
    for (var i = 0; i < 40; i++) {
      await g.moveBy(const Offset(0, -10));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await tester.pumpAndSettle();
    expect(find.byType(Glass), findsNothing);
    final Rect r = tester.getRect(find.byType(DecoratedBox).last);
    expectRect(r, const Rect.fromLTWH(0, 62, 440, 894));
  });

  testWidgets('dragged down it goes; a tap on the dim does too', (
    WidgetTester tester,
  ) async {
    final List<Object?> results = <Object?>[];
    await open(tester, results: results);
    await tester.fling(find.text('Sheet'), const Offset(0, 300), 2000);
    await tester.pumpAndSettle();
    expect(find.text('Sheet'), findsNothing);
    expect(results, <Object?>[null]);

    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();
    expect(find.text('Sheet'), findsOneWidget);
    // A small drag snaps back.
    await tester.drag(find.text('Sheet'), const Offset(0, 40));
    await tester.pumpAndSettle();
    expectRect(sheet(tester), const Rect.fromLTWH(8, 451.08, 424, 496.92));
    await tester.tapAt(const Offset(220, 200));
    await tester.pumpAndSettle();
    expect(find.text('Sheet'), findsNothing);
    expect(results, <Object?>[null, null]);
  });

  testWidgets('it rises on UIKit\'s spring', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1320, 2868);
    tester.view.devicePixelRatio = 3;
    tester.view.padding = const FakeViewPadding(top: 186, bottom: 102);
    addTearDown(tester.view.reset);
    late BuildContext ctx;
    await tester.pumpWidget(
      CupertinoApp(
        home: Builder(
          builder: (BuildContext context) {
            ctx = context;
            return const SizedBox.expand();
          },
        ),
      ),
    );
    showGlassSheet<void>(
      context: ctx,
      builder: (BuildContext context) => const SizedBox.expand(),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    // UIKit, 0.1s into its rise (critically damped, omega 18.1): its top
    // at 451.08 + 505.67 x (1 + 1.81) e^-1.81 = 683.4.
    await tester.pump(const Duration(milliseconds: 100));
    expect(sheet(tester).top, closeTo(683.4, 6));
    await tester.pumpAndSettle();
    expect(sheet(tester).top, closeTo(451.08, 0.05));
  });

  testWidgets('a detent of its own height', (WidgetTester tester) async {
    await open(
      tester,
      detents: const <GlassSheetDetent>[GlassSheetDetent.height(300)],
    );
    // UIKit: 8, 626.15, 424 x 321.85.
    expectRect(sheet(tester), const Rect.fromLTWH(8, 626.15, 424, 321.85));
  });
}
