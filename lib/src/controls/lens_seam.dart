import 'package:flutter/widgets.dart';

import '../lens/lens.dart';

/// THE LENS SEAM: a control's thumb or selection, the liquid lens over the
/// control's own content ([child]: its track, its labels), at [rect] in
/// that content's coordinates. The controls draw their thumb through this
/// one widget, so that how the lens is set up for them is tuned here alone.
///
/// [lift] goes from 0 at rest (the resting pill: an opaque capsule in
/// [color], as UIKit's thumbs and selections are) to 1 lifted into the
/// clear lens, from a `LensLift`, with the lens's own [optics]. [rect] is
/// null when a parent render object places the lens in its layout (the
/// segmented control's box). [flexScale] and [drift] are the thumb's flex
/// along its motion (a `LensFlex`'s) and its rubber-banding. [opacity] dims
/// the whole lens (a disabled control). [shadows] lie under the resting
/// pill (the slider's thumb has one).
///
/// Builds a [LiquidLens] and nothing else: a parent that places the lens
/// expects its render object to be a [RenderLiquidLens].
class ControlLens extends StatelessWidget {
  const ControlLens({
    super.key,
    required this.rect,
    required this.lift,
    required this.optics,
    this.flexScale = const Size(1, 1),
    this.drift = Offset.zero,
    this.opacity = 1,
    this.color,
    this.shadows,
    this.child,
  });

  /// The thumb's bounds in [child]'s coordinates (points): a capsule.
  final Rect? rect;

  /// How lifted the thumb is, 0 to 1.
  final double lift;

  /// The lens's inputs: the small lens's for the switch's and slider's
  /// thumbs, the large one's for a segmented control's selection.
  final LensOptics optics;

  /// The thumb's flex about its center, and its shift.
  final Size flexScale;
  final Offset drift;

  /// How much of the thumb shows, 0 to 1.
  final double opacity;

  /// The resting thumb's color, painted as it is (an opaque white thumb
  /// shows white; a translucent one shows the blurred track through it).
  /// None: UIKit's frosted pill. The lifted lens is clear.
  final Color? color;

  /// Drop shadows under the resting thumb.
  final List<BoxShadow>? shadows;

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final Color? color = this.color;
    Widget? child = this.child;
    // UIKit dims a disabled control as one layer: its opaque thumb still
    // hides the track. Dimmed part by part, the track would show through
    // the thumb, so the track is cut out under the resting thumb.
    final Rect? rect = this.rect;
    if (child != null &&
        rect != null &&
        opacity < 1 &&
        lift <= 0 &&
        color != null &&
        color.a >= 1) {
      child = ClipPath(clipper: _ThumbHole(rect), child: child);
    }
    return LiquidLens(
      rect: rect,
      lift: lift,
      flexScale: flexScale,
      drift: drift,
      optics: optics,
      opacity: opacity,
      indicator: color == null
          ? GlassDecoration(shadows: shadows)
          : GlassDecoration(
              color: color,
              fill: GlassFill.paint,
              shadows: shadows,
            ),
      child: child,
    );
  }
}

/// Everything but the capsule [hole].
class _ThumbHole extends CustomClipper<Path> {
  const _ThumbHole(this.hole);

  final Rect hole;

  @override
  Path getClip(Size size) => Path()
    ..fillType = PathFillType.evenOdd
    ..addRect(hole.inflate(1000).expandToInclude(Offset.zero & size))
    ..addRRect(
      RRect.fromRectAndRadius(hole, Radius.circular(hole.shortestSide / 2)),
    );

  @override
  bool shouldReclip(_ThumbHole oldClipper) => oldClipper.hole != hole;
}

/// [color] at [opacity] times its own alpha: a disabled control's track and
/// labels (its lens dims through [ControlLens.opacity], as the lens may not
/// be painted inside an [Opacity]).
Color dimmed(Color color, double opacity) =>
    opacity >= 1 ? color : color.withValues(alpha: color.a * opacity);
