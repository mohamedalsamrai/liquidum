// ignore: deprecated_member_use
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquidum/liquidum.dart';

// UIKit's popover (iOS 26.5, iPhone 17 Pro Max: 440 x 956, safe area 62 /
// 34), from the catalog's views dumps: its glass (the content's size) by
// the source, the arrow 13pt beyond it to the source's edge, 10pt inside
// the screen's sides and the safe area.
void main() {
  // An app with a 100 x 44 source at [at]; returns the source's context.
  Future<BuildContext> app(WidgetTester tester, Offset at) async {
    tester.view.physicalSize = const Size(1320, 2868);
    tester.view.devicePixelRatio = 3;
    tester.view.padding = const FakeViewPadding(top: 186, bottom: 102);
    addTearDown(tester.view.reset);
    final GlobalKey source = GlobalKey();
    await tester.pumpWidget(
      CupertinoApp(
        home: Stack(
          children: <Widget>[
            Positioned(
              left: at.dx,
              top: at.dy,
              width: 100,
              height: 44,
              child: SizedBox(key: source),
            ),
          ],
        ),
      ),
    );
    return source.currentContext!;
  }

  Rect glass(WidgetTester tester) => tester.getRect(find.byType(Glass));

  Future<Rect> popover(WidgetTester tester, Offset at, Size size) async {
    final BuildContext context = await app(tester, at);
    showGlassPopover<void>(
      context: context,
      size: size,
      builder: (BuildContext context) => const Text('Popover'),
    );
    await tester.pumpAndSettle();
    return glass(tester);
  }

  void expectRect(Rect r, double l, double t, double w, double h) {
    expect(r.left, closeTo(l, 0.01));
    expect(r.top, closeTo(t, 0.01));
    expect(r.width, closeTo(w, 0.01));
    expect(r.height, closeTo(h, 0.01));
  }

  testWidgets('above the source when it fits there, centered', (
    WidgetTester tester,
  ) async {
    // UIKit: [100, 227, 240 x 173] with the arrow below, its tip at 220, 400.
    expectRect(
      await popover(tester, const Offset(170, 400), const Size(240, 160)),
      100,
      227,
      240,
      160,
    );
  });

  testWidgets('below when there is no room above', (WidgetTester tester) async {
    // UIKit: [100, 144, 240 x 173], the arrow above.
    expectRect(
      await popover(tester, const Offset(170, 100), const Size(240, 160)),
      100,
      157,
      240,
      160,
    );
  });

  testWidgets('to the right when only there it is centered on the source', (
    WidgetTester tester,
  ) async {
    // UIKit: [108, 342, 253 x 160], the arrow on the left.
    expectRect(
      await popover(tester, const Offset(8, 400), const Size(240, 160)),
      121,
      342,
      240,
      160,
    );
  });

  testWidgets('moved along when it fits only off center', (
    WidgetTester tester,
  ) async {
    // UIKit: [10, 114, 240 x 173], the arrow's tip at 58, 114.
    expectRect(
      await popover(tester, const Offset(8, 70), const Size(240, 160)),
      10,
      127,
      240,
      160,
    );
  });

  testWidgets('no wider than the screen less 10pt each side', (
    WidgetTester tester,
  ) async {
    // UIKit: [10, 187, 420 x 213].
    expectRect(
      await popover(tester, const Offset(170, 400), const Size(440, 200)),
      10,
      187,
      420,
      200,
    );
  });

  testWidgets('from the source\'s middle when it fits nowhere', (
    WidgetTester tester,
  ) async {
    // UIKit: [220, 72, 210 x 840], the arrow's tip at the source's middle.
    expectRect(
      await popover(tester, const Offset(170, 400), const Size(240, 900)),
      233,
      72,
      197,
      840,
    );
  });

  testWidgets('sized to its content by default', (WidgetTester tester) async {
    final BuildContext context = await app(tester, const Offset(170, 400));
    showGlassPopover<void>(
      context: context,
      builder: (BuildContext context) =>
          const SizedBox(width: 200, height: 120),
    );
    await tester.pumpAndSettle();
    expectRect(glass(tester), 120, 267, 200, 120);
  });

  testWidgets('a tap outside dismisses it; one on it does not', (
    WidgetTester tester,
  ) async {
    final BuildContext context = await app(tester, const Offset(170, 400));
    var done = false;
    showGlassPopover<void>(
      context: context,
      size: const Size(240, 160),
      builder: (BuildContext context) => const Text('Popover'),
    ).then((_) => done = true);
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(220, 300));
    // The arrow, too, is the popover's.
    await tester.tapAt(const Offset(220, 396));
    await tester.pumpAndSettle();
    expect(done, isFalse);
    expect(find.text('Popover'), findsOneWidget);
    await tester.tapAt(const Offset(40, 880));
    await tester.pumpAndSettle();
    expect(done, isTrue);
    expect(find.text('Popover'), findsNothing);
  });

  testWidgets('it grows out of its arrow', (WidgetTester tester) async {
    final BuildContext context = await app(tester, const Offset(170, 400));
    showGlassPopover<void>(
      context: context,
      size: const Size(240, 160),
      builder: (BuildContext context) => const Text('Popover'),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final Rect early = glass(tester);
    // Small, near the arrow's tip.
    expect(early.width, lessThan(240 * 0.5));
    expect(early.center.dx, closeTo(220, 0.5));
    expect(early.bottom, greaterThan(360));
    await tester.pumpAndSettle();
    expectRect(glass(tester), 100, 227, 240, 160);
  });

  testWidgets('an action sheet from a source is a popover without its '
      'cancel action', (WidgetTester tester) async {
    final BuildContext source = await app(tester, const Offset(170, 400));
    GlassAlertAction? chosen;
    var done = false;
    showGlassActionSheet(
      context: source,
      source: source,
      title: 'Title',
      message: 'A message',
      actions: const <GlassAlertAction>[
        GlassAlertAction(label: 'Cancel', cancel: true),
        GlassAlertAction(label: 'OK'),
        GlassAlertAction(label: 'Delete', destructive: true),
      ],
    ).then((GlassAlertAction? a) {
      chosen = a;
      done = true;
    });
    await tester.pumpAndSettle();
    // UIKit: [100, 179, 240 x 221.33]: the glass 208.33 tall above the
    // arrow; the actions stacked, 16pt in, 208 wide.
    // (The test font's lines are not SF's: the glass's height differs.)
    final Rect g = glass(tester);
    expect(g.left, closeTo(100, 0.01));
    expect(g.width, closeTo(240, 0.01));
    expect(g.bottom + 13, closeTo(400, 0.5));
    expect(g.top, g.top.roundToDouble());
    expect(find.text('Cancel'), findsNothing);
    final Rect ok = tester.getRect(
      find
          .ancestor(of: find.text('OK'), matching: find.byType(DecoratedBox))
          .first,
    );
    final Rect delete = tester.getRect(
      find
          .ancestor(
            of: find.text('Delete'),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    expect(ok.left, closeTo(116, 0.01));
    expect(ok.width, closeTo(208, 0.01));
    final Rect message = tester.getRect(find.text('A message'));
    expect(
      message.top - tester.getRect(find.text('Title')).bottom,
      closeTo(7.7, 0.01),
    );
    expect(ok.top - message.bottom, closeTo(20.3, 0.01));
    expect(delete.top - ok.bottom, closeTo(8, 0.01));
    expect(g.bottom - delete.bottom, closeTo(16, 0.01));
    // A tap outside chooses the cancel action.
    await tester.tapAt(const Offset(40, 880));
    await tester.pumpAndSettle();
    expect(done, isTrue);
    expect(chosen?.label, 'Cancel');
  });
}
