import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';

import 'tint_table.dart';

/// UIKit's tinted glass (`UIGlassEffect.tintColor`), as measured on iOS
/// 26.5: a color matrix over the glass that takes its luma L to
/// `dark + (bright - dark) * L`, mixed in at the tint's alpha. In the light
/// appearance `bright` is the tint itself; `dark` is a deeper, more
/// saturated version of it, read from UIKit for a grid of tints and
/// interpolated between them. Exact grays UIKit treats apart: 0.95 of the
/// gray over black glass, and 0.1 + 0.9 of it over white.
@immutable
class GlassTint {
  const GlassTint._(this.dark, this.bright, this.alpha);

  /// No tint.
  static const GlassTint none = GlassTint._(
    <double>[0, 0, 0],
    <double>[0, 0, 0],
    0,
  );

  /// [color]'s tint, in the light or dark appearance.
  factory GlassTint(Color? color, {required bool darkAppearance}) {
    if (color == null || color.a == 0) {
      return none;
    }
    final List<double> t = <double>[color.r, color.g, color.b];
    if (t[0] == t[1] && t[1] == t[2]) {
      final double v = t[0];
      return GlassTint._(
        <double>[0.95 * v, 0.95 * v, 0.95 * v],
        <double>[0.1 + 0.9 * v, 0.1 + 0.9 * v, 0.1 + 0.9 * v],
        color.a,
      );
    }
    final List<double> table = darkAppearance ? tintDark : tintLight;
    final int stride = darkAppearance ? 6 : 3;
    final List<double> v = _interpolate(t, table, stride);
    return GlassTint._(
      v.sublist(0, 3),
      darkAppearance ? v.sublist(3, 6) : t,
      color.a,
    );
  }

  /// [color] as it is: over black glass and white glass alike.
  factory GlassTint.paint(Color? color) => color == null || color.a == 0
      ? none
      : GlassTint._(
          <double>[color.r, color.g, color.b],
          <double>[color.r, color.g, color.b],
          color.a,
        );

  /// The tint's color over black glass, and over white glass (r, g, b).
  final List<double> dark;
  final List<double> bright;

  /// How much of the tinted glass shows over the plain glass.
  final double alpha;

  // The grid's levels, in 255ths.
  static const List<double> _levels = <double>[
    0,
    32 / 255,
    64 / 255,
    96 / 255,
    128 / 255,
    159 / 255,
    191 / 255,
    223 / 255,
    1,
  ];

  // An entry (i >= j >= k) of the table of sorted tints.
  static int _entry(int i, int j, int k) =>
      i * (i + 1) * (i + 2) ~/ 6 + j * (j + 1) ~/ 2 + k;

  // Tetrahedral interpolation of the table at the tint t: over the sorted
  // channels, raising first the one furthest into its cell, so every
  // corner it visits is itself sorted and in the table. Returns the
  // table's values for t's channels in their own order.
  static List<double> _interpolate(
    List<double> t,
    List<double> table,
    int stride,
  ) {
    final order = <int>[0, 1, 2]..sort((int a, int b) => t[b].compareTo(t[a]));
    final cell = List<int>.filled(3, 0);
    final fraction = List<double>.filled(3, 0);
    for (var n = 0; n < 3; n++) {
      final double v = t[order[n]].clamp(0.0, 1.0);
      var i = 0;
      while (i < 7 && v > _levels[i + 1]) {
        i++;
      }
      cell[n] = i;
      fraction[n] = (v - _levels[i]) / (_levels[i + 1] - _levels[i]);
    }
    final steps = <int>[0, 1, 2]
      ..sort((int a, int b) {
        final int c = fraction[b].compareTo(fraction[a]);
        return c != 0 ? c : a.compareTo(b);
      });
    final sorted = List<double>.filled(stride, 0);
    void add(List<int> corner, double weight) {
      final int at = _entry(corner[0], corner[1], corner[2]) * stride;
      for (var c = 0; c < stride; c++) {
        sorted[c] += weight * table[at + c];
      }
    }

    final corner = List<int>.of(cell);
    add(corner, 1 - fraction[steps[0]]);
    for (var s = 0; s < 3; s++) {
      corner[steps[s]]++;
      add(corner, fraction[steps[s]] - (s < 2 ? fraction[steps[s + 1]] : 0));
    }
    // Back to the tint's own channel order, for each group of three.
    final out = List<double>.filled(stride, 0);
    for (var group = 0; group < stride; group += 3) {
      for (var n = 0; n < 3; n++) {
        out[group + order[n]] = sorted[group + n];
      }
    }
    return out;
  }
}
