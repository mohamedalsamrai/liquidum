import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:liquidum/liquidum.dart';

void main() {
  testWidgets('glass brightness follows the system without a backdrop', (
    WidgetTester tester,
  ) async {
    double? seen;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(platformBrightness: Brightness.dark),
        child: GlassBrightness(
          builder: (BuildContext context, double dark, Widget? child) {
            seen = dark;
            return const SizedBox();
          },
        ),
      ),
    );
    expect(seen, 1);
  });

  testWidgets('a surface lays out its child and paints without the shader', (
    WidgetTester tester,
  ) async {
    for (final GlassStyle style in GlassStyle.values) {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: Glass(
                style: style,
                child: const SizedBox(width: 200, height: 60),
              ),
            ),
          ),
        ),
      );
      expect(tester.getSize(find.byType(Glass)), const Size(200, 60));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('a group lays out its glass, and glass appears and leaves', (
    WidgetTester tester,
  ) async {
    Widget build({required bool visible}) => MediaQuery(
      data: const MediaQueryData(),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: GlassGroup(
          spacing: 20,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Glass(child: SizedBox(width: 100, height: 44)),
              const SizedBox(width: 6),
              Glass(
                tint: const Color(0xFF0088FF),
                visible: visible,
                child: const SizedBox(width: 44, height: 44),
              ),
              const SizedBox(width: 6),
              const Glass(
                style: GlassStyle.clear,
                child: SizedBox(width: 44, height: 44),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpWidget(build(visible: false));
    expect(tester.getSize(find.byType(Glass).first), const Size(100, 44));
    await tester.pumpWidget(build(visible: true));
    await tester.pump(Glass.materializeDuration ~/ 2);
    await tester.pump(Glass.materializeDuration);
    await tester.pumpWidget(build(visible: false));
    await tester.pump(Glass.materializeDuration ~/ 2);
    await tester.pump(Glass.materializeDuration);
    // The child stays while the glass is gone.
    expect(tester.getSize(find.byType(Glass).at(1)), const Size(44, 44));
    expect(tester.takeException(), isNull);
  });

  testWidgets('glass can move into and out of a group', (
    WidgetTester tester,
  ) async {
    Widget build({required bool grouped}) {
      const Widget glass = Glass(
        key: ValueKey<String>('glass'),
        child: SizedBox(width: 120, height: 44),
      );
      return MediaQuery(
        data: const MediaQueryData(),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: grouped ? const GlassGroup(child: glass) : glass,
          ),
        ),
      );
    }

    await tester.pumpWidget(build(grouped: false));
    await tester.pumpWidget(build(grouped: true));
    await tester.pumpWidget(build(grouped: false));
    expect(tester.getSize(find.byType(Glass)), const Size(120, 44));
    expect(tester.takeException(), isNull);
  });
}
