import 'package:flutter/widgets.dart';

/// An item in a [GlassPage]'s navigation bar or toolbar, as UIKit's
/// `UIBarButtonItem`: an [icon] or a [label] on the bar's glass.
///
/// ```dart
/// GlassBarItem(icon: CupertinoIcons.add, onPressed: add)
/// GlassBarItem(label: 'Edit', onPressed: edit)
/// GlassBarItem(label: 'Done', prominent: true, onPressed: done)
/// ```
///
/// As in UIKit, icons side by side share one capsule of glass, and a label
/// or a [prominent] item gets one of its own. [GlassBarItem.space] splits a
/// group; in a toolbar it is a flexible space, spreading the groups across
/// the bar.
@immutable
class GlassBarItem {
  const GlassBarItem({
    this.icon,
    this.label,
    required this.onPressed,
    this.prominent = false,
    this.tint,
    this.semanticLabel,
  }) : assert(icon != null || label != null, 'An icon or a label.'),
       _space = false;

  /// Splits groups of items; in a toolbar, a flexible space.
  const GlassBarItem.space()
    : icon = null,
      label = null,
      onPressed = null,
      prominent = false,
      tint = null,
      semanticLabel = null,
      _space = true;

  final IconData? icon;

  /// Shown when there is no [icon]; otherwise the icon's accessibility
  /// label, unless [semanticLabel] is set.
  final String? label;

  /// Called when the item is tapped; null disables it.
  final VoidCallback? onPressed;

  /// UIKit's prominent item (`UIBarButtonItem.Style.prominent`): glass of
  /// its own filled with [tint], under a white icon or label.
  final bool prominent;

  /// A [prominent] item's fill: the system blue by default.
  final Color? tint;

  /// The item's accessibility label, for an icon without a [label].
  final String? semanticLabel;

  final bool _space;

  /// Whether this is a [GlassBarItem.space].
  bool get isSpace => _space;
}
