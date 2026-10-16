import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquidum/liquidum.dart';
import 'package:liquidum/liquidum_debug.dart';
import 'package:liquidum/src/tab_bar/field.dart';
import 'package:liquidum/src/tab_bar/spring.dart';

// The iOS 26.5 simulator's tab bar: 398×62pt, four tabs. Expected values are
// UIKit's, logged every frame from its lens and flex state.
const Size bar = Size(398, 62);

GlassTabBarPhysics makePhysics({int selected = 0}) =>
    GlassTabBarPhysics(count: 4, selectedIndex: selected)..layout(bar, 4);

/// Runs [physics] at 120Hz from [from] for [seconds]; returns the end time.
double run(GlassTabBarPhysics physics, double from, double seconds) {
  var t = from;
  final int frames = (seconds * 120).round();
  for (var i = 0; i < frames; i++) {
    t += 1 / 120;
    physics.tick(t);
  }
  return t;
}

void main() {
  test('tab layout matches UITabBar', () {
    final GlassTabBarPhysics p = makePhysics();
    expect(p.pillWidth, 107.5);
    expect(p.pillHeight, 54);
    expect(p.tabCenter(0), moreOrLessEquals(57.75));
    expect(p.tabCenter(3), moreOrLessEquals(340.25));
    expect(p.tabCenter(1), moreOrLessEquals(151.92, epsilon: 0.01));
  });

  test('pressing lifts the pill into a lens the native size', () {
    final GlassTabBarPhysics p = makePhysics();
    p.tick(0);
    expect(p.lensRect.size, const Size(107.5, 54));
    p.pointerDown(const Offset(57.75, 31));
    run(p, 0, 1.2);
    expect(p.platterScale, moreOrLessEquals(1.0355, epsilon: 1e-4));
    // UIKit, settled: 123.5×70pt bounds in a platter scaled 1.0355, drawn
    // 127.89×72.49pt.
    expect(p.lensRect.width, moreOrLessEquals(127.89, epsilon: 0.05));
    expect(p.lensRect.height, moreOrLessEquals(72.49, epsilon: 0.05));
    expect(p.liftProgress, moreOrLessEquals(1, epsilon: 1e-3));
    // Under the finger; UIKit's swollen platter carries its lens to 52.73.
    expect(p.lensRect.center.dx, moreOrLessEquals(57.75, epsilon: 0.01));
  });

  test('the platter swells with an overshoot and settles back under', () {
    final GlassTabBarPhysics p = makePhysics();
    p.tick(0);
    p.pointerDown(const Offset(200, 31));
    var t = 0.0, peak = 0.0;
    for (var i = 0; i < 60; i++) {
      t += 1 / 120;
      p.tick(t);
      peak = peak > p.platterScale ? peak : p.platterScale;
    }
    // UIKit peaks at 1.0384 about 0.2s in.
    expect(peak, moreOrLessEquals(1.0384, epsilon: 0.0006));
    t = run(p, t, 0.5);
    p.pointerUp();
    var low = 2.0;
    for (var i = 0; i < 60; i++) {
      t += 1 / 120;
      p.tick(t);
      low = low < p.platterScale ? low : p.platterScale;
    }
    // And dips about 9% of the swell below rest on release.
    expect(low, moreOrLessEquals(1 - 0.0355 * 0.094, epsilon: 0.0008));
  });

  test('the lens follows the finger one to one once it has caught up', () {
    final GlassTabBarPhysics p = makePhysics();
    p.tick(0);
    p.pointerDown(const Offset(60, 31));
    var t = run(p, 0, 1.5);
    for (var x = 60.0; x <= 250; x += 3) {
      p.pointerMove(Offset(x, 31));
      t += 1 / 120;
      p.tick(t);
      // As drawn, in the swollen platter.
      expect(
        p.toBar(Offset(p.lensX, 0)).dx,
        moreOrLessEquals(x, epsilon: 1e-3),
      );
    }
  });

  test('the lens stops where the resting pill meets the platter edge', () {
    final GlassTabBarPhysics p = makePhysics(selected: 3);
    p.tick(0);
    p.pointerDown(const Offset(340, 31));
    var t = run(p, 0, 1.5);
    p.pointerMove(const Offset(430, 31));
    t = run(p, t, 1.5);
    expect(p.lensX, moreOrLessEquals(398 - 53.75, epsilon: 1e-3));
    // The platter stretches and drifts after the finger: 90pt moved, 32pt
    // of it past the end.
    const k = 2.77e-5 * 90 + 8.2e-5 * 32;
    expect(p.platterDrift.dx, moreOrLessEquals(1.075 * k * 398, epsilon: 0.01));
    expect(p.platterScaleX, moreOrLessEquals(1.0355 * (1 + k), epsilon: 1e-4));
    expect(p.platterScaleY, moreOrLessEquals(1.0355 / (1 + k), epsilon: 1e-4));
  });

  test('a tap selects the tapped tab and stays clear for the hang time', () {
    final GlassTabBarPhysics p = makePhysics();
    p.tick(0);
    p.pointerDown(const Offset(246, 31));
    var t = run(p, 0, 0.05);
    expect(p.pointerUp(), 2);
    t = run(p, t, 0.15);
    // Within the hang time the lens is still clear.
    expect(p.clear, greaterThan(0.9));
    t = run(p, t, 1.6);
    expect(p.clear, lessThan(0.01));
    expect(p.lensX, moreOrLessEquals(p.tabCenter(2), epsilon: 0.05));
    expect(p.lensInPlatter.width, moreOrLessEquals(107.5, epsilon: 0.05));
    expect(p.lensInPlatter.height, moreOrLessEquals(54, epsilon: 0.05));
    expect(p.isActive, isFalse);
  });

  test('releasing a drag picks the nearest tab and drops the lens', () {
    final GlassTabBarPhysics p = makePhysics();
    p.tick(0);
    p.pointerDown(const Offset(57.75, 31));
    var t = run(p, 0, 0.5);
    p.pointerMove(const Offset(180, 31));
    t = run(p, t, 0.3);
    expect(p.pointerUp(), 1);
    t = run(p, t, 2.5);
    final Rect lens = p.lensRect;
    expect(lens.center.dx, moreOrLessEquals(p.tabCenter(1), epsilon: 0.05));
    expect(lens.width, moreOrLessEquals(107.5, epsilon: 0.05));
    expect(lens.height, moreOrLessEquals(54, epsilon: 0.05));
    expect(p.platterScale, moreOrLessEquals(1, epsilon: 1e-4));
    expect(p.isActive, isFalse);
  });

  test('pressing an end tab kicks the lens narrow and tall', () {
    // The swelling platter carries the Home lens outward; UIKit's flex
    // answers with x 0.964, y 1.059 at first.
    final GlassTabBarPhysics p = makePhysics();
    p.tick(0);
    p.pointerDown(const Offset(57.75, 31));
    var t = 0.0, lowest = 1.0;
    for (var i = 0; i < 24; i++) {
      t += 1 / 120;
      p.tick(t);
      lowest = lowest < p.flexScale.width ? lowest : p.flexScale.width;
    }
    expect(lowest, lessThan(0.995));
  });

  test('moving right flattens the lens, stopping makes it tall', () {
    final GlassTabBarPhysics p = makePhysics();
    p.tick(0);
    p.pointerDown(const Offset(57.75, 31));
    var t = run(p, 0, 1.2);
    final double restHeight = p.lensRect.height;
    // 800pt/s for 0.35s, sampled at 120Hz.
    var x = 57.75;
    var minHeight = double.infinity;
    for (var i = 0; i < 42; i++) {
      x += 800 / 120;
      p.pointerMove(Offset(x, 31));
      t += 1 / 120;
      p.tick(t);
      minHeight = minHeight < p.lensRect.height ? minHeight : p.lensRect.height;
    }
    expect(minHeight, lessThan(restHeight - 10));
    var maxHeight = 0.0;
    for (var i = 0; i < 60; i++) {
      t += 1 / 120;
      p.tick(t);
      maxHeight = maxHeight > p.lensRect.height ? maxHeight : p.lensRect.height;
    }
    expect(maxHeight, greaterThan(restHeight + 5));
  });

  test('springs step the same at any frame rate', () {
    GlassSpring make() =>
        GlassSpring(response: 0.3, dampingRatio: 0.6)..target = 1;
    final GlassSpring a = make(), b = make();
    for (var i = 0; i < 12; i++) {
      a.step(1 / 120);
    }
    for (var i = 0; i < 3; i++) {
      b.step(1 / 30);
    }
    expect(a.value, moreOrLessEquals(b.value, epsilon: 1e-9));
    expect(a.velocity, moreOrLessEquals(b.velocity, epsilon: 1e-9));
    // UIKit's lift spring is critically damped with a 0.25s response.
    final lift = GlassSpring.physical(
      mass: 1,
      stiffness: 631.654682,
      damping: 50.265482,
    );
    expect(lift.response, moreOrLessEquals(0.25, epsilon: 1e-6));
    expect(lift.dampingRatio, moreOrLessEquals(1, epsilon: 1e-5));
  });

  test('tabs are sized as UIKit sizes them', () {
    // UIKit, iOS 26.5: bar widths for up to three tabs, and the tab buttons'
    // widths and spacing.
    expect(GlassTabBarPhysics.naturalWidth(1, 30), 102);
    expect(GlassTabBarPhysics.naturalWidth(2, 30), 188);
    expect(GlassTabBarPhysics.naturalWidth(3, 30), 274);
    expect(
      GlassTabBarPhysics.naturalWidth(3, 88.33),
      moreOrLessEquals(374, epsilon: 0.01),
    );
    expect(GlassTabBarPhysics.naturalWidth(4, 30), isNull);
    for (final (int count, double width, double pill, double spacing)
        in <(int, double, double, double)>[
          (3, 274, 94, 86),
          (3, 238, 82, 74),
          (4, 398, 107.5, 94.17),
          (4, 360, 98, 84.67),
          (5, 398, 84.6, 76.35),
          (5, 360, 77, 68.75),
        ]) {
      final p = GlassTabBarPhysics(count: count, selectedIndex: 0)
        ..layout(Size(width, 62), count);
      expect(p.pillWidth, moreOrLessEquals(pill, epsilon: 0.01));
      expect(p.tabCenter(0), moreOrLessEquals(4 + pill / 2, epsilon: 0.01));
      expect(
        p.tabCenter(1) - p.tabCenter(0),
        moreOrLessEquals(spacing, epsilon: 0.01),
      );
    }
  });

  test('padding moves the tabs in and grows the bar', () {
    const padding = EdgeInsets.fromLTRB(12, 10, 20, 6);
    expect(
      GlassTabBarPhysics.naturalWidth(3, 30, horizontal: padding.horizontal),
      3 * 94 - 16 + 32,
    );
    final p = GlassTabBarPhysics(count: 3, selectedIndex: 0)
      ..layout(const Size(298, 54 + 16), 3, padding: padding);
    expect(p.pillHeight, 54);
    expect(p.pillWidth, 94);
    expect(p.tabCenter(0), 12 + 47);
    expect(p.tabCenter(2), 298 - 20 - 47);
    expect(p.tabMiddle, 10 + 27);
    expect(p.lensRect.center.dy, moreOrLessEquals(37, epsilon: 1e-9));
  });

  test('the lifted lens rises out of a padded bar as out of UIKit\'s', () {
    // How far the lifted lens rises past the platter's top and bottom, in
    // the platter's own points.
    (double, double) rise(EdgeInsets padding) {
      final size = Size(274 + padding.horizontal - 8, 54 + padding.vertical);
      final p = GlassTabBarPhysics(count: 3, selectedIndex: 0)
        ..layout(size, 3, padding: padding);
      p.tick(0);
      p.pointerDown(Offset(141, size.height / 2), time: 0);
      run(p, 0, 0.6);
      final Rect lens = p.lensRect, bar = p.platterRect;
      return (
        (bar.top - lens.top) / p.platterScaleY,
        (lens.bottom - bar.bottom) / p.platterScaleY,
      );
    }

    final (double top, double bottom) = rise(const EdgeInsets.all(4));
    // UIKit's: 4pt, and the flex.
    expect(top, greaterThan(4));
    expect(bottom, greaterThan(4));
    for (final padding in <EdgeInsets>[
      const EdgeInsets.all(8),
      const EdgeInsets.fromLTRB(8, 12, 8, 6),
    ]) {
      final (double t, double b) = rise(padding);
      expect(t, moreOrLessEquals(top, epsilon: 0.5));
      expect(b, moreOrLessEquals(bottom, epsilon: 0.5));
    }
  });

  test('capsule distances', () {
    final shape = GlassShape(const Rect.fromLTWH(0, 0, 100, 40));
    expect(shape.radius, 20);
    expect(shape.distance(const Offset(50, 20)), -20);
    expect(shape.distance(const Offset(50, -5)), moreOrLessEquals(5));
    expect(shape.distance(const Offset(-5, 20)), moreOrLessEquals(5));
    expect(
      shape.distance(const Offset(20, 20) + const Offset(-18, -24)),
      moreOrLessEquals(10),
    );
    expect(shape.normal(const Offset(50, 0)), const Offset(0, -1));
    final Offset oval = shape.normal(const Offset(80, 0), ovalization: 0.5);
    expect(oval.dx, greaterThan(0));
    expect(oval.distance, moreOrLessEquals(1));
  });

  testWidgets('the bar selects the tab the finger lets go over', (
    WidgetTester tester,
  ) async {
    var selected = 0;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 398,
              child: StatefulBuilder(
                builder: (BuildContext context, StateSetter setState) =>
                    GlassTabBar(
                      items: const <GlassTabItem>[
                        GlassTabItem(icon: SizedBox(), label: 'Home'),
                        GlassTabItem(icon: SizedBox(), label: 'New'),
                        GlassTabItem(icon: SizedBox(), label: 'Radio'),
                        GlassTabItem(icon: SizedBox(), label: 'Library'),
                      ],
                      selectedIndex: selected,
                      onSelected: (int i) => setState(() => selected = i),
                    ),
              ),
            ),
          ),
        ),
      ),
    );
    final Rect rect = tester.getRect(find.byType(GlassTabBar));
    expect(rect.size, const Size(398, 62));
    final TestGesture finger = await tester.startGesture(
      rect.topLeft + const Offset(57.75, 31),
    );
    await tester.pump(const Duration(milliseconds: 300));
    for (var x = 60.0; x <= 250; x += 10) {
      await finger.moveTo(rect.topLeft + Offset(x, 31));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await finger.up();
    await tester.pumpAndSettle();
    expect(selected, 2);
    expect(tester.takeException(), isNull);
  });

  test('a press washes and glows as UIKit does, under the finger', () {
    final GlassTabBarPhysics p = makePhysics();
    p.tick(0);
    expect(p.press, 0);
    p.pointerDown(const Offset(57.75, 31));
    // UIKit: up within 0.18s (0.51 at 50ms, 0.95 at 100ms).
    run(p, 0, 0.1);
    expect(p.press, moreOrLessEquals(0.93, epsilon: 0.04));
    var t = run(p, 0.1, 0.5);
    expect(p.press, moreOrLessEquals(1, epsilon: 1e-3));
    expect(p.glowCenter, const Offset(57.75, 31));
    // 93pt in the swollen platter, at 0.2845.
    expect(p.glowSize, moreOrLessEquals(96.3, epsilon: 0.05));
    expect(p.glowAlpha, moreOrLessEquals(0.2845, epsilon: 1e-3));

    // Leaving the tab spreads it to twice the size, at half the opacity.
    for (var x = 57.75; x <= 250; x += 2) {
      p.pointerMove(Offset(x, 31));
      t = run(p, t, 1 / 60);
    }
    t = run(p, t, 1.0);
    expect(p.glowSize, moreOrLessEquals(193.6, epsilon: 0.5));
    expect(p.glowAlpha, moreOrLessEquals(0.1422, epsilon: 1e-3));

    // Let go: it stays where the finger left, spreads to four times and
    // fades over about half a second.
    p.pointerUp();
    t = run(p, t, 0.15);
    expect(p.press, inExclusiveRange(0.3, 0.8));
    run(p, t, 1.2);
    expect(p.press, moreOrLessEquals(0, epsilon: 1e-3));
    expect(p.glowCenter!.dx, 249.75);
    expect(p.glowSize, moreOrLessEquals(372, epsilon: 1));
  });

  test('a press that stays on its tab keeps the glow small', () {
    final GlassTabBarPhysics p = makePhysics();
    p.tick(0);
    p.pointerDown(const Offset(57.75, 31));
    var t = run(p, 0, 0.3);
    p.pointerMove(const Offset(90, 31));
    t = run(p, t, 1);
    // (The platter stretches a little toward the finger.)
    expect(p.glowSize, moreOrLessEquals(96.3, epsilon: 0.2));
  });
}
