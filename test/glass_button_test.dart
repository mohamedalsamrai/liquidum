import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquidum/liquidum.dart';

void main() {
  Widget app(Widget child) => CupertinoApp(
    home: Center(child: child),
  );

  testWidgets('glass buttons have UIKit sizes', (WidgetTester tester) async {
    await tester.pumpWidget(
      app(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            GlassButton(label: 'Medium', onPressed: () {}),
            GlassButton(icon: CupertinoIcons.add, onPressed: () {}),
            GlassButton(
              label: 'Large',
              size: GlassButtonSize.large,
              onPressed: () {},
            ),
            GlassButton(
              icon: CupertinoIcons.add,
              size: GlassButtonSize.small,
              onPressed: () {},
            ),
          ],
        ),
      ),
    );
    final List<Size> sizes = <Size>[
      for (final Element e in find.byType(Glass).evaluate())
        (e.renderObject! as RenderBox).size,
    ];
    expect(sizes[0].height, closeTo(38.33, 0.01));
    expect(sizes[1], const Size(34.33, 34.33));
    expect(sizes[2].height, closeTo(54.33, 0.01));
    expect(sizes[3], const Size(28, 28));
  });

  testWidgets('a glass button taps, and swells while pressed', (
    WidgetTester tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      app(GlassButton(label: 'Tap', onPressed: () => taps++)),
    );
    final Finder glass = find.byType(Glass);
    final Rect rest = tester.getRect(glass);
    final TestGesture gesture = await tester.startGesture(rest.center);
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    // UIKit's ultra small glass swells by 16pt along its long side.
    final RenderBox box = tester.renderObject(
      find
          .descendant(
            of: glass,
            matching: find.byWidgetPredicate(
              (Widget w) => w.runtimeType.toString() == '_GlassLabel',
            ),
          )
          .first,
    );
    final double swollen =
        MatrixUtils.transformRect(
          box.getTransformTo(null),
          Offset.zero & box.size,
        ).width /
        box.size.width;
    expect(swollen, closeTo((rest.width + 16) / rest.width, 0.01));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(taps, 1);
    final double after =
        MatrixUtils.transformRect(
          box.getTransformTo(null),
          Offset.zero & box.size,
        ).width /
        box.size.width;
    expect(after, 1);
  });

  testWidgets('a glass button without onPressed is disabled', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      app(const GlassButton(label: 'Off', onPressed: null)),
    );
    final Finder off = find.bySemanticsLabel('Off');
    expect(off, findsOneWidget);
    expect(
      tester.getSemantics(off),
      matchesSemantics(
        label: 'Off',
        isButton: true,
        hasEnabledState: true,
        isEnabled: false,
      ),
    );
    expect(tester.getSize(find.byType(Glass)).height, closeTo(38.33, 0.01));
    semantics.dispose();
  });
}
