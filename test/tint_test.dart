import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:liquidum/src/tab_bar/tint.dart';

// UIKit's tint matrices (UIGlassEffect.tintColor, iOS 26.5 simulator): the
// color over black glass and over white glass, for tints between the
// measured grid's points.
void main() {
  void expectTint(
    GlassTint t, {
    required List<double> dark,
    required List<double> bright,
    double epsilon = 0.005,
  }) {
    for (var c = 0; c < 3; c++) {
      expect(t.dark[c], moreOrLessEquals(dark[c], epsilon: epsilon));
      expect(t.bright[c], moreOrLessEquals(bright[c], epsilon: epsilon));
    }
  }

  test('light: the tint over white glass, deeper over black', () {
    expectTint(
      GlassTint(const Color(0xFFFF3366), darkAppearance: false),
      dark: <double>[0.7553, -0.0353, 0.0988],
      bright: <double>[1, 0.2, 0.4],
    );
    expectTint(
      GlassTint(const Color(0xFFE0A040), darkAppearance: false),
      dark: <double>[0.5884, 0.3568, 0.0096],
      bright: <double>[0.8784, 0.6275, 0.2510],
      epsilon: 0.01,
    );
    // Its channels in another order: the same values, in that order.
    expectTint(
      GlassTint(const Color(0xFF3366FF), darkAppearance: false),
      dark: <double>[-0.0353, 0.0988, 0.7553],
      bright: <double>[0.2, 0.4, 1],
    );
  });

  test('dark appearance', () {
    expectTint(
      GlassTint(const Color(0xFFFF3366), darkAppearance: true),
      dark: <double>[1.0043, 0.1658, 0.3754],
      bright: <double>[0.9759, 0.3941, 0.5395],
    );
  });

  test('exact grays are apart, nearby colors are not', () {
    expectTint(
      GlassTint(const Color(0xFF808080), darkAppearance: false),
      dark: <double>[0.4769, 0.4769, 0.4769],
      bright: <double>[0.5518, 0.5518, 0.5518],
    );
    expectTint(
      GlassTint(const Color(0xFF808081), darkAppearance: false),
      dark: <double>[0.2654, 0.2654, 0.2681],
      bright: <double>[0.502, 0.502, 0.5059],
      epsilon: 0.01,
    );
  });

  test('alpha and no color', () {
    expect(
      GlassTint(const Color(0x80FF3366), darkAppearance: false).alpha,
      moreOrLessEquals(0.502, epsilon: 0.001),
    );
    expect(GlassTint(null, darkAppearance: false).alpha, 0);
  });

  test('a painted color is itself over any glass', () {
    final t = GlassTint.paint(const Color(0xC21E1E1E));
    expect(t.bright, t.dark);
    expect(t.bright[0], moreOrLessEquals(0x1E / 255, epsilon: 1e-6));
    expect(t.alpha, moreOrLessEquals(0xC2 / 255, epsilon: 1e-6));
  });
}
