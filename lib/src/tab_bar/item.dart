import 'package:flutter/widgets.dart';

import 'style.dart';

/// A tab in a [GlassTabBar]: its icon, label and badge, and colors of its
/// own where they should differ from the bar's [GlassTabBarStyle].
@immutable
class GlassTabItem {
  const GlassTabItem({
    required this.icon,
    this.selectedIcon,
    required this.label,
    this.badge,
    this.badgeColor,
    this.selectedColor,
    this.unselectedColor,
    this.tintIcon = true,
  });

  /// Drawn centered 24pt below the top of the bar, as UIKit centers a tab's
  /// symbol. Use an [Icon], or anything else that takes its color from the
  /// ambient [IconTheme]: the bar colors it as UIKit colors template images.
  /// For an icon with colors of its own, turn off [tintIcon].
  final Widget icon;

  /// The icon while the tab is selected (for example, a filled variant), as
  /// `UITabBarItem.selectedImage`. Defaults to [icon].
  final Widget? selectedIcon;

  /// Shown under the icon, and read by screen readers.
  final String label;

  /// A badge at the icon's top trailing corner, as `UITabBarItem.badgeValue`:
  /// a count or a short word. None when null.
  final String? badge;

  /// This tab's badge color, instead of [GlassTabBarStyle.badgeColor].
  final Color? badgeColor;

  /// This tab's [GlassTabBarStyle.selectedColor].
  final Color? selectedColor;

  /// This tab's [GlassTabBarStyle.unselectedColor].
  final Color? unselectedColor;

  /// Whether the bar colors the icon. Turn it off for icons with colors of
  /// their own, such as a profile photo: they are drawn as they are, as
  /// UIKit draws images in their original rendering mode.
  final bool tintIcon;
}
