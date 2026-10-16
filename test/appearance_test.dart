import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:liquidum/liquidum_debug.dart';

// Expected values are UIKit's (iOS 26.5 simulator), read from its tab bar's
// filters over flat and stepped backdrops.

/// Feeds [luma] and runs [appearance] at 120Hz for [seconds] from [from].
double settle(
  GlassAppearance appearance,
  double luma,
  double from, {
  double seconds = 2,
}) {
  appearance.sample(luma);
  var t = from;
  for (var i = 0; i < seconds * 120; i++) {
    t += 1 / 120;
    appearance.tick(t);
  }
  return t;
}

void main() {
  test('the platter face follows the luma in 1/32 steps', () {
    final a = GlassAppearance()..tick(0);
    var t = settle(a, 0.498, 0); // a flat 0x7f backdrop: 16/32
    expect(a.isDark, isFalse);
    var (double black, double white, double fill, double gray) = a.face;
    expect(black, moreOrLessEquals(0.3661, epsilon: 2e-4));
    expect(white, moreOrLessEquals(0.9661, epsilon: 2e-4));
    expect(fill, moreOrLessEquals(0.4919, epsilon: 2e-3));
    expect(gray, 1);
    // 0x7f and 0x80 read the same.
    t = settle(a, 0.502, t);
    expect(a.face.$1, moreOrLessEquals(0.3661, epsilon: 2e-4));
    // White: UIKit's values on white, which Stage 3's face was fitted to.
    t = settle(a, 1, t);
    (black, white, fill, gray) = a.face;
    expect(black, 0.85);
    expect(white, 1.03);
    expect(fill, 0.25);
    expect(a.shadow, moreOrLessEquals(0.46875 * (0.093 + 0.966 * 0.05)));
  });

  test('light turns dark below 0.210 and back above 0.492', () {
    final a = GlassAppearance()..tick(0);
    var t = settle(a, 0.8, 0);
    for (final double l in <double>[0.22, 0.212]) {
      t = settle(a, l, t);
      expect(a.isDark, isFalse, reason: 'at $l');
    }
    t = settle(a, 0.208, t);
    expect(a.isDark, isTrue);
    // Its dark face: black 0.1, white 0.45 + 1.032 L, a black fill.
    final (double black, double white, double fill, double gray) = a.face;
    expect(black, 0.1);
    expect(white, moreOrLessEquals(0.45 + 1.032 * 7 / 32, epsilon: 1e-3));
    expect(fill, moreOrLessEquals(0.25 + 0.367 * 7 / 32, epsilon: 1e-3));
    expect(gray, moreOrLessEquals(0, epsilon: 1e-3));
    for (final double l in <double>[0.3, 0.47, 0.490]) {
      t = settle(a, l, t);
      expect(a.isDark, isTrue, reason: 'at $l');
    }
    settle(a, 0.494, t);
    expect(a.isDark, isFalse);
  });

  test('in dark mode the bar turns light only over bright backdrops', () {
    final a = GlassAppearance(system: Brightness.dark)..tick(0);
    expect(a.isDark, isTrue);
    var t = settle(a, 0.863, 0);
    expect(a.isDark, isTrue);
    t = settle(a, 0.871, t);
    expect(a.isDark, isFalse);
    t = settle(a, 0.588, t);
    expect(a.isDark, isFalse);
    settle(a, 0.580, t);
    expect(a.isDark, isTrue);
  });

  test('a change takes effect after a moment and settles on a 0.5s spring', () {
    final a = GlassAppearance()..tick(0);
    var t = settle(a, 1, 0);
    a.sample(0);
    // UIKit: the symbols switch 50-90ms after the change, the glass is half
    // way about 0.15s after it starts.
    var switched = double.nan;
    var half = double.nan;
    final double start = t;
    for (var i = 0; i < 120; i++) {
      t += 1 / 120;
      a.tick(t);
      if (switched.isNaN && a.isDark) {
        switched = t - start;
      }
      if (half.isNaN && a.face.$1 < (0.85 + 0.1) / 2) {
        half = t - start;
      }
    }
    expect(switched, inInclusiveRange(0.045, 0.07));
    expect(half - switched, inInclusiveRange(0.13, 0.19));
  });

  test('the sampled area is the bar grown as UIKit grows its container', () {
    const bar = Rect.fromLTWH(21, 873, 398, 62);
    expect(
      GlassAppearance.sampleArea(bar),
      const Rect.fromLTRB(0, 860.6, 440, 956),
    );
  });

  test('a reading that changes nothing is known as such', () {
    final a = GlassAppearance()..tick(0);
    // Before the first reading, any reading changes something.
    expect(a.wouldKeep(1), isFalse);
    var t = settle(a, 0.6, 0);
    expect(a.wouldKeep(0.6), isTrue);
    expect(a.wouldKeep(0.61), isFalse);
    // While another reading waits to take effect, the old luma is no
    // longer the one that will hold.
    a.sample(0.1);
    expect(a.wouldKeep(0.6), isFalse);
    expect(a.wouldKeep(0.1), isFalse);
    t = settle(a, 0.1, t);
    expect(a.wouldKeep(0.1), isTrue);
  });
}
