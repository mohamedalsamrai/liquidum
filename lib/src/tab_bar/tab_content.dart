import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'item.dart';
import 'style.dart';

/// The four layers a tab's content is drawn in, each a row of the content
/// atlas the bar's shader reads.
///
/// UIKit draws template content (symbols and labels) through color matrices
/// over the glass below it, and the rest (badges, images in their original
/// colors) as it is. Template layers only give the shader their shapes, and
/// for the selected tabs the tint, as their color; the others are drawn as
/// they are.
enum TabLayer {
  normalTemplate,
  selectedTemplate,
  normalOriginal,
  selectedOriginal;

  bool get selected =>
      this == TabLayer.selectedTemplate || this == TabLayer.selectedOriginal;

  bool get original =>
      this == TabLayer.normalOriginal || this == TabLayer.selectedOriginal;

  /// The layer's row in the content atlas: selected template, normal
  /// template, selected original, normal original.
  int get row => switch (this) {
    TabLayer.selectedTemplate => 0,
    TabLayer.normalTemplate => 1,
    TabLayer.selectedOriginal => 2,
    TabLayer.normalOriginal => 3,
  };
}

/// What [layer] of [item] holds, laid out as UITabBar lays out a tab on iOS
/// 26: the symbol centered 24pt below the top of the bar; the label in a
/// 12pt line from 39pt (38.7 here, for Flutter's line metrics), 10pt with
/// SF's small-size tracking, which Flutter's text engine does not apply by
/// itself; the badge 6pt below the top of the bar, overlapping the symbol's
/// trailing edge by 5pt.
class TabContent extends StatelessWidget {
  const TabContent({
    super.key,
    required this.item,
    required this.layer,
    required this.style,
    required this.dark,
  });

  final GlassTabItem item;
  final TabLayer layer;
  final GlassTabBarStyle style;

  /// Whether the bar is in its dark appearance, for dynamic colors.
  final bool dark;

  // UIKit's normal symbols over its plain light and dark glass, for when
  // the shader is not available to color them.
  static const Color _normalLight = Color(0xFF191919);
  static const Color _normalDark = Color(0xFFF3F3F3);

  /// The labels' style: UIKit's 10pt, semibold when selected and medium
  /// otherwise, with SF's small-size tracking, merged with the bar's.
  static TextStyle labelStyle(
    GlassTabBarStyle style, {
    required bool selected,
  }) => TextStyle(
    fontSize: 10,
    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
    letterSpacing: 0.1,
    height: 1.2,
  ).merge(style.labelStyle);

  /// Whether [item] puts anything in an original layer.
  static bool hasOriginal(GlassTabItem item, GlassTabBarStyle style) =>
      item.badge != null ||
      !item.tintIcon ||
      (item.unselectedColor ?? style.unselectedColor) != null;

  @override
  Widget build(BuildContext context) {
    final bool selected = layer.selected;
    final Widget icon = selected ? item.selectedIcon ?? item.icon : item.icon;
    // A set unselected color is drawn as it is, not as a template.
    final Color? flat = selected
        ? null
        : item.unselectedColor ?? style.unselectedColor;
    final bool templateIcon = item.tintIcon && flat == null;
    final bool templateLabel = flat == null;
    final bool drawIcon = layer.original != templateIcon;
    final bool drawLabel = layer.original != templateLabel;
    final String? badge = layer.original ? item.badge : null;

    final Color color = GlassTabBarStyle.resolve(
      selected
          ? item.selectedColor ??
                style.selectedColor ??
                GlassTabBarStyle.systemBlue
          : flat ?? (dark ? _normalDark : _normalLight),
      dark: dark,
    );

    return CustomMultiChildLayout(
      delegate: _TabLayout(Directionality.of(context)),
      children: <Widget>[
        if (drawIcon || badge != null)
          LayoutId(
            id: _Part.icon,
            // Laid out even when another layer draws it: the badge is placed
            // by it.
            child: _Unpainted(
              unpainted: !drawIcon,
              child: IconTheme.merge(
                data: IconThemeData(color: color, size: 26),
                child: icon,
              ),
            ),
          ),
        if (drawLabel)
          LayoutId(
            id: _Part.label,
            child: Text(
              item.label,
              maxLines: 1,
              softWrap: false,
              textAlign: TextAlign.center,
              overflow: TextOverflow.visible,
              style: labelStyle(
                style,
                selected: selected,
              ).copyWith(color: color),
            ),
          ),
        if (badge != null)
          LayoutId(
            id: _Part.badge,
            child: TabBadge(
              text: badge,
              color: GlassTabBarStyle.resolve(
                item.badgeColor ??
                    style.badgeColor ??
                    GlassTabBarStyle.systemRed,
                dark: dark,
              ),
            ),
          ),
      ],
    );
  }
}

enum _Part { icon, label, badge }

/// Lays its child out but paints it only when not [unpainted]. (Unlike
/// [Opacity], it never makes the child a repaint boundary: the content
/// atlas must hear of every repaint in a tab.)
class _Unpainted extends SingleChildRenderObjectWidget {
  const _Unpainted({required this.unpainted, super.child});

  final bool unpainted;

  @override
  _RenderUnpainted createRenderObject(BuildContext context) =>
      _RenderUnpainted(unpainted);

  @override
  void updateRenderObject(BuildContext context, _RenderUnpainted renderObject) {
    renderObject.unpainted = unpainted;
  }
}

class _RenderUnpainted extends RenderProxyBox {
  _RenderUnpainted(this._unpainted);

  bool get unpainted => _unpainted;
  bool _unpainted;
  set unpainted(bool value) {
    if (value != _unpainted) {
      _unpainted = value;
      markNeedsPaint();
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (!_unpainted) {
      super.paint(context, offset);
    }
  }
}

class _TabLayout extends MultiChildLayoutDelegate {
  _TabLayout(this.direction);

  final TextDirection direction;

  static const double _symbolCenter = 24;
  static const double _labelTop = 38.7;
  static const double _labelHeight = 12;
  static const double _labelOverhang = 20;
  static const double _badgeTop = 6;
  static const double _badgeOverlap = 5;

  @override
  void performLayout(Size size) {
    final double center = size.width / 2;
    Rect? icon;
    if (hasChild(_Part.icon)) {
      final Size s = layoutChild(_Part.icon, BoxConstraints.loose(size));
      icon = Rect.fromCenter(
        center: Offset(center, _symbolCenter),
        width: s.width,
        height: s.height,
      );
      positionChild(_Part.icon, icon.topLeft);
    }
    if (hasChild(_Part.label)) {
      final double width = size.width + 2 * _labelOverhang;
      final Size s = layoutChild(
        _Part.label,
        BoxConstraints(maxWidth: width, maxHeight: _labelHeight),
      );
      positionChild(
        _Part.label,
        Offset(center - s.width / 2, _labelTop + (_labelHeight - s.height) / 2),
      );
    }
    if (hasChild(_Part.badge)) {
      final Size s = layoutChild(_Part.badge, const BoxConstraints());
      final Rect at = icon ?? Rect.fromLTWH(center, _symbolCenter, 0, 0);
      positionChild(
        _Part.badge,
        Offset(
          direction == TextDirection.rtl
              ? at.left + _badgeOverlap - s.width
              : at.right - _badgeOverlap,
          _badgeTop,
        ),
      );
    }
  }

  @override
  bool shouldRelayout(_TabLayout oldDelegate) =>
      oldDelegate.direction != direction;
}

/// UIKit's tab bar badge: [text] in white 12pt medium, centered on a
/// capsule 20⅓pt high and at least as wide, with 4pt on either side of the
/// text.
class TabBadge extends StatelessWidget {
  const TabBadge({super.key, required this.text, required this.color});

  final String text;
  final Color color;

  static const double height = 20 + 1 / 3;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: height),
      child: DecoratedBox(
        decoration: ShapeDecoration(color: color, shape: const StadiumBorder()),
        child: SizedBox(
          height: height,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Center(
              widthFactor: 1,
              child: Text(
                text,
                maxLines: 1,
                softWrap: false,
                textAlign: TextAlign.center,
                // The font's own line, centered, as UILabel does.
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFFFFFFFF),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The content atlas's rows hold [TabLayer]s; this many.
const int tabLayerCount = 4;

/// Whether any of [items] puts anything in an original layer.
bool anyOriginal(List<GlassTabItem> items, GlassTabBarStyle style) =>
    items.any((GlassTabItem i) => TabContent.hasOriginal(i, style));
