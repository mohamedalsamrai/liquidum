import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquidum/src/lens/lens.dart';

void main() {
  testWidgets('a lens lays out its child and paints without the shader', (
    WidgetTester tester,
  ) async {
    for (final double lift in <double>[0, 0.5, 1]) {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: LiquidLens(
                rect: const Rect.fromLTWH(2, 2, 37, 24),
                lift: lift,
                flexScale: const Size(1.1, 0.95),
                drift: const Offset(2, 0),
                indicator: const GlassDecoration(color: Color(0xFFFFFFFF)),
                decoration: const GlassDecoration(
                  gradient: LinearGradient(
                    colors: <Color>[Color(0xFFD82789), Color(0xFF7257A8)],
                  ),
                  shadows: <BoxShadow>[
                    BoxShadow(color: Color(0x1A000000), blurRadius: 6),
                  ],
                  innerShadows: <BoxShadow>[
                    BoxShadow(color: Color(0x40FFFFFF), blurRadius: 1),
                  ],
                ),
                child: const SizedBox(width: 63, height: 28),
              ),
            ),
          ),
        ),
      );
      expect(tester.getSize(find.byType(LiquidLens)), const Size(63, 28));
      expect(tester.takeException(), isNull);
    }
    final RenderLiquidLens lens = tester.renderObject(find.byType(LiquidLens));
    // The lens as drawn: the rect flexed about its center and drifted.
    expect(lens.drawnRect.center, const Offset(22.5, 14));
    expect(lens.drawnRect.width, closeTo(40.7, 0.01));
    expect(lens.drawnRect.height, closeTo(22.8, 0.01));
  });

  test('the small lens lifts with 8% overshoot at 0.17s and falls back', () {
    final LensLift lift = LensLift();
    // UIKit's lens starts its lift a frame after the touch.
    lift.down(time: 0);
    // The lift progress is clamped; the bounds' growth, on the same
    // spring, shows the overshoot.
    var peak = 0.0;
    var peakAt = 0.0;
    for (var i = 0; i <= 120; i++) {
      final double t = i / 120;
      lift.tick(t);
      if (lift.growth > peak) {
        peak = lift.growth;
        peakAt = t;
      }
      if (t < LensLift.liftDelay) {
        expect(lift.lift, 0);
      }
    }
    expect(peak, closeTo(1.08, 0.01));
    expect(peakAt - LensLift.liftDelay, closeTo(0.173, 0.012));
    expect(lift.lift, closeTo(1, 0.002));
    expect(lift.growth, closeTo(1, 0.002));
    expect(lift.pressed, isTrue);

    // Held long enough: it falls back as soon as the finger leaves, on the
    // unlift spring (157.91 / 17.59: 4.6% under at 0.35s, within a
    // hundredth by 0.5s, at rest within about a second).
    lift.up(time: 1);
    var under = 0.0;
    for (var i = 121; i <= 264; i++) {
      lift.tick(i / 120);
      under = lift.growth < under ? lift.growth : under;
      if (i == 180) {
        expect(lift.lift, lessThan(0.01));
      }
    }
    expect(under, closeTo(-0.046, 0.006));
    expect(lift.lift, 0);
    expect(lift.pressed, isFalse);
    expect(lift.isActive, isFalse);
  });

  test('a quick tap keeps the lens lifted for the hang time', () {
    final LensLift lift = LensLift();
    lift.down(time: 0);
    lift.up(time: 0.05);
    var lifted = false;
    for (var i = 1; i <= 36; i++) {
      // Up to 0.3s: lifted (hanging) until 0.27s.
      lift.tick(i / 120);
      if (i / 120 < 0.05 + LensLift.defaultHangTime - 0.02) {
        lifted |= lift.lift > 0.9;
      }
    }
    expect(lifted, isTrue);
    expect(lift.lift, lessThan(0.9));
    for (var i = 37; i <= 240; i++) {
      lift.tick(i / 120);
    }
    expect(lift.lift, 0);
    expect(lift.isActive, isFalse);
  });

  test('the large lens is the tab bar\'s: critically damped', () {
    final LensLift lift = LensLift(variant: LensVariant.large);
    lift.down(time: 0);
    var peak = 0.0;
    for (var i = 0; i <= 60; i++) {
      lift.tick(i / 120);
      peak = peak > lift.lift ? peak : lift.lift;
    }
    expect(peak, closeTo(1, 0.001));
    expect(lift.lift, closeTo(1, 0.001));
  });

  test('reduce motion keeps the lens down', () {
    final LensLift lift = LensLift()..reduceMotion = true;
    lift.down(time: 0);
    for (var i = 0; i <= 60; i++) {
      lift.tick(i / 120);
    }
    expect(lift.lift, 0);
    expect(lift.pressed, isTrue);
  });
}
