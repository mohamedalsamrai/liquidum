import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquidum/liquidum.dart';

// UIKit's compact date picker (iOS 26.5, iPhone 17 Pro Max, en_US): the
// calendar platter is 320 x 332 large glass; its top 6.17pt below the
// label's middle (above it, its bottom 5.83pt over the middle, when below
// would come within 90pt of the safe area's bottom); its right edge 6pt
// short of the label's middle, 20pt from the screen's sides. It grows from
// 0.2 on a spring (omega 19.56, damping 0.798) and its glass unfolds from
// 0.15 of its height.
void main() {
  late List<DateTime> changes;

  Future<void> pump(
    WidgetTester tester, {
    Offset at = const Offset(32, 200),
    DateTime? value,
    GlassDatePickerMode mode = GlassDatePickerMode.date,
    DateTime? firstDate,
  }) async {
    tester.view.physicalSize = const Size(440, 956);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 62, bottom: 34);
    addTearDown(tester.view.reset);
    changes = <DateTime>[];
    DateTime v = value ?? DateTime(2026, 11, 4, 9, 41);
    await tester.pumpWidget(
      CupertinoApp(
        home: StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) => Stack(
            children: <Widget>[
              const Positioned.fill(
                child: ColoredBox(color: Color(0xFFFFFFFF)),
              ),
              Positioned(
                left: at.dx,
                top: at.dy,
                child: GlassDatePicker(
                  value: v,
                  mode: mode,
                  firstDate: firstDate,
                  onChanged: (DateTime d) {
                    changes.add(d);
                    setState(() => v = d);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Rect platter(WidgetTester tester) => tester.getRect(find.byType(Glass).last);

  testWidgets('the calendar opens below the label, as UIKit\'s', (
    WidgetTester tester,
  ) async {
    await pump(tester);
    final Rect label = tester.getRect(find.bySemanticsLabel('Nov 4, 2026'));
    expect(label.height, closeTo(34.33, 0.01));
    await tester.tap(find.bySemanticsLabel('Nov 4, 2026'));
    await tester.pumpAndSettle();
    final Rect r = platter(tester);
    expect(r.width, closeTo(320, 1e-6));
    expect(r.height, closeTo(332, 1e-6));
    expect(r.top, closeTo(label.center.dy + 6.17, 0.01));
    expect(r.left, 20);
    expect(find.text('November 2026'), findsOneWidget);
    expect(find.text('WED'), findsOneWidget);
  });

  testWidgets('it grows from 0.2, its glass unfolding from its top', (
    WidgetTester tester,
  ) async {
    await pump(tester);
    await tester.tap(find.bySemanticsLabel('Nov 4, 2026'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    // UIKit, 78ms after its start: scale 0.485, the glass 155 x 73.
    await tester.pump(const Duration(milliseconds: 68));
    final Rect r = platter(tester);
    final double s = r.width / 320;
    final double p = (s - 0.2) / 0.8;
    expect(r.height / (332 * s), closeTo(0.15 + 0.85 * p, 0.01));
    expect(s, inInclusiveRange(0.3, 0.7));
    await tester.pumpAndSettle();
  });

  testWidgets('a day is chosen and the calendar stays; a tap outside closes', (
    WidgetTester tester,
  ) async {
    await pump(tester);
    await tester.tap(find.bySemanticsLabel('Nov 4, 2026'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('20 November 2026'));
    await tester.pumpAndSettle();
    expect(changes.single, DateTime(2026, 11, 20, 9, 41));
    expect(find.text('November 2026'), findsOneWidget);
    expect(find.bySemanticsLabel('Nov 20, 2026'), findsOneWidget);
    await tester.tapAt(const Offset(420, 900));
    await tester.pumpAndSettle();
    expect(find.text('November 2026'), findsNothing);
    expect(find.byType(Glass), findsNothing);
  });

  testWidgets('the arrows page months; the title shows the wheels', (
    WidgetTester tester,
  ) async {
    await pump(tester);
    await tester.tap(find.bySemanticsLabel('Nov 4, 2026'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Next Month'));
    await tester.pumpAndSettle();
    expect(find.text('December 2026'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Previous Month'));
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpAndSettle();
    expect(find.text('November 2026'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('November 2026'));
    await tester.pumpAndSettle();
    // UIKit's month and year wheels: a year further on shows its month.
    expect(find.byType(CupertinoPicker), findsNWidgets(2));
    // (The drag less the touch slop moves one row.)
    await tester.drag(find.text('2026'), const Offset(0, -50));
    await tester.pumpAndSettle();
    expect(find.text('November 2027'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('November 2027'));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoPicker), findsNothing);
    expect(changes, isEmpty);
  });

  testWidgets('low on the screen it opens above the label', (
    WidgetTester tester,
  ) async {
    await pump(tester, at: const Offset(32, 500));
    await tester.tap(find.bySemanticsLabel('Nov 4, 2026'));
    await tester.pumpAndSettle();
    final Rect label = tester.getRect(find.bySemanticsLabel('Nov 4, 2026'));
    // UIKit: a label at 500 puts the calendar's bottom at 511.33.
    expect(platter(tester).bottom, closeTo(label.center.dy - 5.83, 0.01));
  });

  testWidgets('near the right edge it keeps short of the label\'s middle', (
    WidgetTester tester,
  ) async {
    await pump(tester, at: const Offset(308.67, 100));
    await tester.tap(find.bySemanticsLabel('Nov 4, 2026'));
    await tester.pumpAndSettle();
    final Rect label = tester.getRect(find.bySemanticsLabel('Nov 4, 2026'));
    expect(platter(tester).right, closeTo(label.center.dx - 6, 0.01));
  });

  testWidgets('the time opens UIKit\'s wheels; days before the first are off', (
    WidgetTester tester,
  ) async {
    await pump(tester, mode: GlassDatePickerMode.dateAndTime);
    expect(find.bySemanticsLabel('9:41 AM'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('9:41 AM'));
    await tester.pumpAndSettle();
    expect(platter(tester).width, closeTo(232, 1e-6));
    expect(platter(tester).height, closeTo(204, 1e-6));
    // UIKit's time wheels: turning the minutes changes the time.
    expect(find.byType(CupertinoPicker), findsNWidgets(3));
    await tester.drag(find.text('41').last, const Offset(0, -50));
    await tester.pumpAndSettle();
    expect(changes.last, DateTime(2026, 11, 4, 9, 42));
    expect(find.bySemanticsLabel('9:42 AM'), findsOneWidget);
    // Past 12 the period turns: 9 up three hours is 12 PM.
    await tester.drag(find.text('9').last, const Offset(0, -114));
    await tester.pumpAndSettle();
    expect(changes.last, DateTime(2026, 11, 4, 12, 42));
    expect(find.bySemanticsLabel('12:42 PM'), findsOneWidget);
    await tester.tapAt(const Offset(420, 900));
    await tester.pumpAndSettle();
    expect(find.byType(Glass), findsNothing);

    changes.clear();
    await pump(tester, firstDate: DateTime(2026, 11, 3));
    await tester.tap(find.bySemanticsLabel('Nov 4, 2026'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('2 November 2026'));
    await tester.pumpAndSettle();
    expect(changes, isEmpty);
    expect(find.bySemanticsLabel('Previous Month'), findsOneWidget);
  });
}
