import 'package:flutter/widgets.dart';

import 'tab_bar.dart';

/// What [GlassTabBar] draws for its glass while it is being built up.
enum GlassTabBarDebugView {
  /// The glass: the bar's pass and the lens's pass over one shared backdrop
  /// capture (neutral placeholders until the optics are in).
  none,

  /// The glass field flat: platter, pill and lens silhouettes.
  field,

  /// The lens's surface normals as colors.
  normals,

  /// The sampling architecture made visible: the bar's glass hatched (so a
  /// pass reading rendered glass would show it), the lens pass marking what
  /// it shows from outside itself, an inspector with the capture both passes
  /// read, and the glass field, sampling region and finger drawn twice (by
  /// the shaders in capture pixels, and by the canvas in layout
  /// coordinates) so that any mismatch shows.
  sampling,
}

/// The optical stages of the glass, as bits of
/// [GlassTabBarDebugOptions.optics].
abstract final class GlassTabBarOptics {
  /// The lens's warp: samples pushed outward near its edge.
  static const int warp = 1;

  /// The lens's inner refraction, and its material's tone.
  static const int inner = 2;

  /// The lens's chromatic dispersion.
  static const int dispersion = 4;

  /// The platter's material (refraction, frost, color); without it, the
  /// backdrop is seen bare.
  static const int platter = 8;

  /// The resting selection's tint.
  static const int rest = 16;

  /// The lifted content: the selected tab grown and lensed by the lens.
  static const int content = 32;

  /// The lit rims of the platter and the lens.
  static const int rim = 64;

  /// The shadows of the platter and the lens.
  static const int shadow = 128;

  /// The press: the wash over the platter and the fingertip glow.
  static const int press = 256;

  static const int all = 511;
}

/// Measurement and debugging settings for a [GlassTabBar], given to it by a
/// [GlassTabBarDebug] above it.
@immutable
class GlassTabBarDebugOptions {
  const GlassTabBarDebugOptions({
    this.view = GlassTabBarDebugView.none,
    this.shareBackdrop = true,
    this.inspector,
    this.hold,
    this.hideContent = false,
    this.optics = GlassTabBarOptics.all,
    this.lift,
  });

  /// What the bar draws for its glass.
  final GlassTabBarDebugView view;

  /// Whether the lens reads the same backdrop capture as the bar, taken
  /// before any of the bar's glass. Turn off only to see what the lens would
  /// read otherwise: the bar's rendered glass.
  final bool shareBackdrop;

  /// Where [GlassTabBarDebugView.sampling] draws its inspector, in the bar's
  /// coordinates. Defaults to a panel above the bar.
  final Rect? inspector;

  /// Holds a press at this point, in the bar's coordinates, from the first
  /// frame on: the lens stays lifted there without a real touch, for still
  /// comparisons.
  final Offset? hold;

  /// Draws no tab content, so the glass's optics can be looked at alone.
  final bool hideContent;

  /// The optical stages drawn (a [GlassTabBarOptics] mask), to compare them
  /// one at a time.
  final int optics;

  /// Draws the glass's optics at this lift progress (0 to 1) instead of the
  /// lens's, to compare the transition between resting and lifted at fixed
  /// points.
  final double? lift;

  @override
  bool operator ==(Object other) =>
      other is GlassTabBarDebugOptions &&
      other.view == view &&
      other.shareBackdrop == shareBackdrop &&
      other.inspector == inspector &&
      other.hold == hold &&
      other.hideContent == hideContent &&
      other.optics == optics &&
      other.lift == lift;

  @override
  int get hashCode => Object.hash(
    view,
    shareBackdrop,
    inspector,
    hold,
    hideContent,
    optics,
    lift,
  );
}

/// Gives [options] to the [GlassTabBar]s below it.
class GlassTabBarDebug extends InheritedWidget {
  const GlassTabBarDebug({
    super.key,
    required this.options,
    required super.child,
  });

  final GlassTabBarDebugOptions options;

  /// The options of the closest [GlassTabBarDebug], or the defaults.
  static GlassTabBarDebugOptions of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GlassTabBarDebug>()?.options ??
      const GlassTabBarDebugOptions();

  @override
  bool updateShouldNotify(GlassTabBarDebug oldWidget) =>
      options != oldWidget.options;
}
