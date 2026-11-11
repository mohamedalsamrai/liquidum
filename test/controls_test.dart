import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquidum/liquidum.dart';
import 'package:liquidum/src/lens/lens.dart';

void main() {
  Widget app(Widget child) => CupertinoApp(home: Center(child: child));

  /// Pumps frames until the motion settles (at most [seconds]).
  Future<void> settle(WidgetTester tester, [double seconds = 2]) async {
    for (var i = 0; i < seconds * 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  /// A press moved through [path] (offsets from [from]), then let go.
  Future<void> dragPath(
    WidgetTester tester,
    Offset from,
    List<Offset> path,
  ) async {
    final TestGesture g = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 16));
    for (final Offset o in path) {
      await g.moveTo(from + o);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await settle(tester);
  }

  /// A press moved by [by] in four steps, then let go.
  Future<void> drag(WidgetTester tester, Offset from, Offset by) => dragPath(
    tester,
    from,
    <Offset>[for (var i = 1; i <= 4; i++) by * (i / 4)],
  );

  group('GlassSwitch', () {
    testWidgets('is UIKit\'s size and toggles on a tap', (
      WidgetTester tester,
    ) async {
      bool? got;
      await tester.pumpWidget(
        app(GlassSwitch(value: false, onChanged: (bool v) => got = v)),
      );
      expect(tester.getSize(find.byType(GlassSwitch)), const Size(63, 28));
      await tester.tap(find.byType(GlassSwitch));
      await settle(tester);
      expect(got, isTrue);
    });

    testWidgets('a drag past the middle toggles; one back again does not', (
      WidgetTester tester,
    ) async {
      final List<bool> got = <bool>[];
      await tester.pumpWidget(
        app(GlassSwitch(value: false, onChanged: got.add)),
      );
      final Rect r = tester.getRect(find.byType(GlassSwitch));
      // The thumb starts at the left end; its travel is 22pt, so 12pt is
      // past the middle (as UIKit's 12pt drag toggled).
      await drag(tester, Offset(r.left + 20, r.center.dy), const Offset(12, 0));
      expect(got, <bool>[true]);
      got.clear();
      await dragPath(tester, Offset(r.left + 20, r.center.dy), const <Offset>[
        Offset(10, 0),
        Offset(20, 0),
        Offset(8, 0),
        Offset(2, 0),
      ]);
      expect(got, isEmpty);
    });

    testWidgets('the thumb lifts for a tap and travels 22pt', (
      WidgetTester tester,
    ) async {
      var on = false;
      await tester.pumpWidget(
        app(
          StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) =>
                GlassSwitch(
                  value: on,
                  onChanged: (bool v) => setState(() => on = v),
                ),
          ),
        ),
      );
      RenderLiquidLens lens() =>
          tester.renderObject<RenderLiquidLens>(find.byType(LiquidLens));
      final Rect rest = lens().rect;
      expect(rest.size, const Size(37, 24));
      expect(rest.left, 2);
      final Rect r = tester.getRect(find.byType(GlassSwitch));
      final TestGesture g = await tester.startGesture(r.center);
      await tester.pump(const Duration(milliseconds: 16));
      await g.up();
      // A tap keeps the lens lifted for about 0.15s after the touch.
      await tester.pump(const Duration(milliseconds: 80));
      expect(lens().lift, greaterThan(0.5));
      await settle(tester);
      expect(on, isTrue);
      expect(lens().lift, 0);
      expect(lens().rect.left, closeTo(24, 0.01));
      expect(lens().rect.size, const Size(37, 24));
    });

    testWidgets('follows its value, and ignores touches when disabled', (
      WidgetTester tester,
    ) async {
      var on = false;
      await tester.pumpWidget(
        app(
          StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) =>
                GlassSwitch(
                  value: on,
                  onChanged: (bool v) => setState(() => on = v),
                ),
          ),
        ),
      );
      // The thumb is the liquid lens's rect, in the switch's coordinates.
      Rect thumb() => tester
          .renderObject<RenderLiquidLens>(find.byType(LiquidLens))
          .drawnRect;
      final double before = thumb().left;
      await tester.tap(find.byType(GlassSwitch));
      await settle(tester);
      expect(on, isTrue);
      expect(thumb().left, greaterThan(before + 15));

      await tester.pumpWidget(
        app(const GlassSwitch(value: true, onChanged: null)),
      );
      await tester.tap(find.byType(GlassSwitch));
      await settle(tester);
      expect(tester.widget<GlassSwitch>(find.byType(GlassSwitch)).value, true);
    });

    testWidgets('has toggle semantics', (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpWidget(
        app(GlassSwitch(value: true, onChanged: (bool v) {})),
      );
      expect(
        tester.getSemantics(find.byType(GlassSwitch)),
        matchesSemantics(
          hasToggledState: true,
          isToggled: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );
      handle.dispose();
    });
  });

  group('GlassSlider', () {
    Widget slider({
      double value = 0,
      ValueChanged<double>? onChanged,
      int? divisions,
      ValueChanged<double>? onChangeEnd,
    }) => SizedBox(
      width: 237,
      child: GlassSlider(
        value: value,
        onChanged: onChanged,
        divisions: divisions,
        onChangeEnd: onChangeEnd,
      ),
    );

    testWidgets('is 34pt tall and follows a drag of its thumb', (
      WidgetTester tester,
    ) async {
      var value = 0.0;
      double? ended;
      await tester.pumpWidget(
        app(
          StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) => slider(
              value: value,
              onChanged: (double v) => setState(() => value = v),
              onChangeEnd: (double v) => ended = v,
            ),
          ),
        ),
      );
      final Rect r = tester.getRect(find.byType(GlassSlider));
      expect(r.height, 34);
      // The thumb's center travels 200pt (237 less the 37pt thumb): 100pt
      // is half.
      await drag(
        tester,
        Offset(r.left + 18.5, r.center.dy),
        const Offset(100, 0),
      );
      expect(value, closeTo(0.5, 0.01));
      expect(ended, closeTo(0.5, 0.01));
    });

    testWidgets('snaps to divisions, and a touch on the track does nothing', (
      WidgetTester tester,
    ) async {
      final List<double> got = <double>[];
      await tester.pumpWidget(app(slider(onChanged: got.add, divisions: 4)));
      final Rect r = tester.getRect(find.byType(GlassSlider));
      await drag(
        tester,
        Offset(r.left + 18.5, r.center.dy),
        const Offset(60, 0),
      );
      expect(got, isNotEmpty);
      expect(
        got.every((double v) => (v * 4 - (v * 4).round()).abs() < 1e-9),
        isTrue,
      );
      expect(got.last, 0.25);
      got.clear();
      await drag(
        tester,
        Offset(r.right - 20, r.center.dy),
        const Offset(-60, 0),
      );
      expect(got, isEmpty);
    });

    testWidgets('ignores touches when disabled, and has slider semantics', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpWidget(app(slider(value: 0.5)));
      final Rect r = tester.getRect(find.byType(GlassSlider));
      await drag(tester, Offset(r.center.dx, r.center.dy), const Offset(50, 0));
      expect(tester.widget<GlassSlider>(find.byType(GlassSlider)).value, 0.5);
      expect(
        tester.getSemantics(find.byType(GlassSlider)),
        matchesSemantics(
          isSlider: true,
          hasEnabledState: true,
          isEnabled: false,
          value: '50%',
        ),
      );
      handle.dispose();
    });
  });

  group('GlassSegmentedControl', () {
    Widget control({
      String? value = 'One',
      ValueChanged<String>? onValueChanged,
      double? width,
    }) => SizedBox(
      width: width,
      child: GlassSegmentedControl<String>(
        children: const <String, Widget>{
          'One': Text('One'),
          'Two': Text('Two'),
          'Three': Text('Three'),
        },
        groupValue: value,
        onValueChanged: onValueChanged,
      ),
    );

    testWidgets('is 32pt tall, as wide as its segments, and selects on tap', (
      WidgetTester tester,
    ) async {
      String? got;
      await tester.pumpWidget(
        app(control(onValueChanged: (String v) => got = v)),
      );
      final Rect r = tester.getRect(find.byType(GlassSegmentedControl<String>));
      expect(r.height, 32);
      final double three = tester.getSize(find.text('Three')).width;
      expect(r.width, closeTo(3 * (three + 20), 0.5));
      await tester.tap(find.text('Two'));
      await settle(tester);
      expect(got, 'Two');
    });

    testWidgets('fills a given width, and a dragged selection snaps', (
      WidgetTester tester,
    ) async {
      var value = 'One';
      await tester.pumpWidget(
        app(
          StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) => control(
              value: value,
              width: 300,
              onValueChanged: (String v) => setState(() => value = v),
            ),
          ),
        ),
      );
      final Rect r = tester.getRect(find.byType(GlassSegmentedControl<String>));
      expect(r.width, 300);
      // From the selected segment (the first, 100pt wide) to the third.
      await drag(
        tester,
        Offset(r.left + 50, r.center.dy),
        const Offset(190, 0),
      );
      expect(value, 'Three');
      // A drag from an unselected segment does not lift or move the lens;
      // the segment under the finger when it leaves is selected.
      await drag(
        tester,
        Offset(r.left + 50, r.center.dy),
        const Offset(100, 0),
      );
      expect(value, 'Two');
    });

    testWidgets('the label under a dragged selection turns medium', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        app(control(width: 300, onValueChanged: (String v) {})),
      );
      FontWeight? weight(String label) => tester
          .widget<RichText>(
            find.descendant(
              of: find.text(label),
              matching: find.byType(RichText),
            ),
          )
          .text
          .style
          ?.fontWeight;
      expect(weight('One'), FontWeight.w500);
      expect(weight('Two'), FontWeight.w400);
      final Rect r = tester.getRect(find.byType(GlassSegmentedControl<String>));
      final TestGesture g = await tester.startGesture(
        Offset(r.left + 50, r.center.dy),
      );
      await tester.pump(const Duration(milliseconds: 16));
      for (var i = 1; i <= 4; i++) {
        await g.moveTo(Offset(r.left + 50 + 25.0 * i, r.center.dy));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(weight('One'), FontWeight.w400);
      expect(weight('Two'), FontWeight.w500);
      await g.up();
      await settle(tester);
      // The owner kept 'One': its label is medium again.
      expect(weight('One'), FontWeight.w500);
      expect(weight('Two'), FontWeight.w400);
    });

    testWidgets('selects on touch-up, and only the selected segment lifts', (
      WidgetTester tester,
    ) async {
      var value = 'One';
      await tester.pumpWidget(
        app(
          StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) => control(
              value: value,
              width: 300,
              onValueChanged: (String v) => setState(() => value = v),
            ),
          ),
        ),
      );
      RenderLiquidLens lens() =>
          tester.renderObject<RenderLiquidLens>(find.byType(LiquidLens));
      final Rect r = tester.getRect(find.byType(GlassSegmentedControl<String>));
      // The pill: the first segment (100pt) inset 2.
      expect(lens().rect, const Rect.fromLTWH(2, 2, 96, 28));
      // A press on an unselected segment: nothing until the finger leaves.
      TestGesture g = await tester.startGesture(
        Offset(r.left + 250, r.center.dy),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(value, 'One');
      expect(lens().lift, 0);
      await g.up();
      await settle(tester);
      expect(value, 'Three');
      expect(lens().rect.left, closeTo(202, 0.01));
      // A press on the selected segment lifts it (the large lens: lifted
      // within a quarter second).
      g = await tester.startGesture(Offset(r.left + 250, r.center.dy));
      for (var i = 0; i < 14; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(lens().lift, greaterThan(0.5));
      expect(lens().rect.width, greaterThan(96 + 20));
      await g.up();
      await settle(tester);
      expect(lens().lift, 0);
      expect(value, 'Three');
    });

    testWidgets('ignores touches when disabled, and has selection semantics', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpWidget(app(control()));
      await tester.tap(find.text('Two'));
      await settle(tester);
      expect(
        tester
            .widget<GlassSegmentedControl<String>>(
              find.byType(GlassSegmentedControl<String>),
            )
            .groupValue,
        'One',
      );
      expect(
        tester.getSemantics(find.text('One')),
        matchesSemantics(
          label: 'One',
          isButton: true,
          isSelected: true,
          isInMutuallyExclusiveGroup: true,
          hasEnabledState: true,
          isEnabled: false,
          hasSelectedState: true,
        ),
      );
      handle.dispose();
    });
  });
}
