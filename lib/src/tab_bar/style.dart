import 'dart:math' as math;

import 'package:flutter/cupertino.dart' show CupertinoDynamicColor;
import 'package:flutter/widgets.dart';

/// A [GlassTabBar]'s colors and label style, for its tabs' content (see the
/// bar's parameters of the same names). Null values take UIKit's defaults.
@immutable
class GlassTabBarStyle {
  const GlassTabBarStyle({
    this.selectedColor,
    this.unselectedColor,
    this.badgeColor,
    this.labelStyle,
  });

  /// UIKit's default tint on iOS 26: the system blue of its light and dark
  /// appearances.
  static const CupertinoDynamicColor systemBlue =
      CupertinoDynamicColor.withBrightnessAndContrast(
        color: Color(0xFF0088FF),
        darkColor: Color(0xFF0091FF),
        highContrastColor: Color(0xFF1E6EF4),
        darkHighContrastColor: Color(0xFF5CB8FF),
      );

  /// UIKit's badge color: the system red of its light and dark appearances.
  static const CupertinoDynamicColor systemRed =
      CupertinoDynamicColor.withBrightness(
        color: Color(0xFFFF383C),
        darkColor: Color(0xFFFF4245),
      );

  final Color? selectedColor;
  final Color? unselectedColor;
  final Color? badgeColor;
  final TextStyle? labelStyle;

  /// [color] in the bar's light or dark appearance, and with Increase
  /// Contrast ([contrast]) as UIKit shows selected tabs then: a dynamic
  /// color's high-contrast variant if it has one; any other color with its
  /// hue kept and, in OKLab, its lightness times 0.796 and chroma times 0.82
  /// in the light appearance (within 3 levels of UIKit's, iOS 26.5), or
  /// lightness 0.788 L + 0.274 and chroma times 0.894 in the dark one
  /// (approximate: within 13 levels).
  static Color resolve(
    Color color, {
    required bool dark,
    bool contrast = false,
  }) {
    if (color is CupertinoDynamicColor) {
      final Color plain = dark ? color.darkColor : color.color;
      if (!contrast) {
        return plain;
      }
      final Color high = dark
          ? color.darkHighContrastColor
          : color.highContrastColor;
      return high != plain ? high : _contrasted(plain, dark: dark);
    }
    return contrast ? _contrasted(color, dark: dark) : color;
  }

  static Color _contrasted(Color c, {required bool dark}) {
    double lin(double v) => v <= 0.04045
        ? v / 12.92
        : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    double srgb(double v) {
      final double x = v.clamp(0.0, 1.0);
      return x <= 0.0031308 ? 12.92 * x : 1.055 * math.pow(x, 1 / 2.4) - 0.055;
    }

    final double r = lin(c.r), g = lin(c.g), b = lin(c.b);
    double l = math
        .pow(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b, 1 / 3)
        .toDouble();
    double m = math
        .pow(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b, 1 / 3)
        .toDouble();
    double s = math
        .pow(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b, 1 / 3)
        .toDouble();
    double lightness = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s;
    double a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s;
    double bb = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s;
    final double kl = dark ? 0.788 : 0.796, kc = dark ? 0.894 : 0.82;
    lightness = math.min(lightness * kl + (dark ? 0.274 : 0), 1);
    a *= kc;
    bb *= kc;
    l = math
        .pow(lightness + 0.3963377774 * a + 0.2158037573 * bb, 3)
        .toDouble();
    m = math
        .pow(lightness - 0.1055613458 * a - 0.0638541728 * bb, 3)
        .toDouble();
    s = math
        .pow(lightness - 0.0894841775 * a - 1.2914855480 * bb, 3)
        .toDouble();
    return Color.from(
      alpha: c.a,
      red: srgb(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
      green: srgb(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
      blue: srgb(-0.0041960863 * l - 0.7034186367 * m + 1.7076147010 * s),
    );
  }
}
