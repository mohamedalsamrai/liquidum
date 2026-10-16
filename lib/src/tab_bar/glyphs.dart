import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// A magnifying glass and a cross, sized like those in the iOS 26 tab bar's
/// search tab and search field (measured from screenshots in the iOS 26.5
/// simulator): a ring of 0.735 of the glyph's size with a round-capped
/// handle to its corner, and a cross of round-capped strokes. Colored from
/// the [IconTheme].
class BarGlyph extends StatelessWidget {
  /// The search tab's magnifying glass in its circle: 22.3pt, 2pt strokes.
  const BarGlyph.search({super.key, this.size = 22.3, this.stroke = 2})
    : _close = false;

  /// The search field's magnifying glass: 17.5pt, 1.5pt strokes.
  const BarGlyph.field({super.key, this.size = 17.5, this.stroke = 1.5})
    : _close = false;

  /// The search field's close button: 16.7pt across, 1.7pt strokes.
  const BarGlyph.close({super.key, this.size = 16.7, this.stroke = 1.7})
    : _close = true;

  final double size;
  final double stroke;
  final bool _close;

  @override
  Widget build(BuildContext context) {
    final Color color = IconTheme.of(context).color ?? const Color(0xFF000000);
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _GlyphPainter(color: color, stroke: stroke, close: _close),
      ),
    );
  }
}

class _GlyphPainter extends CustomPainter {
  const _GlyphPainter({
    required this.color,
    required this.stroke,
    required this.close,
  });

  final Color color;
  final double stroke;
  final bool close;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = stroke;
    final double s = size.shortestSide;
    if (close) {
      final double a = stroke / 2, b = s - stroke / 2;
      canvas
        ..drawLine(Offset(a, a), Offset(b, b), paint)
        ..drawLine(Offset(b, a), Offset(a, b), paint);
      return;
    }
    final double outer = 0.735 * s / 2;
    final double r = outer - stroke / 2;
    final Offset c = Offset(outer, outer);
    canvas.drawCircle(c, r, paint);
    final Offset edge =
        c + Offset(math.cos(math.pi / 4), math.sin(math.pi / 4)) * outer;
    canvas.drawLine(
      edge,
      Offset(s - stroke * 0.6, s - stroke * 0.6),
      paint..strokeWidth = stroke * 1.2,
    );
  }

  @override
  bool shouldRepaint(_GlyphPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.stroke != stroke ||
      oldDelegate.close != close;
}
