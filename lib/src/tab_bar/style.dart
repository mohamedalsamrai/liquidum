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
      CupertinoDynamicColor.withBrightness(
        color: Color(0xFF0088FF),
        darkColor: Color(0xFF0091FF),
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

  /// [color] in the bar's light or dark appearance.
  static Color resolve(Color color, {required bool dark}) =>
      color is CupertinoDynamicColor
      ? (dark ? color.darkColor : color.color)
      : color;
}
