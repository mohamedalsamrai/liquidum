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
}
