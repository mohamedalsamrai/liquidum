import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:liquidum/liquidum.dart';

void main() {
  test('materials interpolate between presets', () {
    const a = GlassMaterial.regular;
    const b = GlassMaterial.clear;
    expect(GlassMaterial.lerp(a, b, 0), a);
    expect(GlassMaterial.lerp(a, b, 1), b);
    expect(GlassMaterial.lerp(a, b, 0.5).blur, (a.blur + b.blur) / 2);
  });

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
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(child: Glass(child: SizedBox(width: 200, height: 60))),
      ),
    );
    expect(tester.getSize(find.byType(Glass)), const Size(200, 60));
    expect(tester.takeException(), isNull);
  });
}
