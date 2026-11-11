import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../shader_program.dart';

/// UIKit's scroll-edge effect (iOS 26's soft edge) over the content under a
/// bar: a soft step at [edge] (points from the top of this box), the bar's
/// side blurred a little and dimmed, or washed toward the page's background
/// [washColor]. Paint it over the content and under the bar's glass.
///
/// [blur], [black] and [wash] are how much of each shows, already faded as
/// the effect comes and goes. [barAbove] is true for an effect under a top
/// bar.
class ScrollEdgeEffect extends LeafRenderObjectWidget {
  const ScrollEdgeEffect({
    super.key,
    required this.edge,
    required this.barAbove,
    required this.blur,
    required this.black,
    required this.wash,
    required this.washColor,
  });

  final double edge;
  final bool barAbove;
  final double blur;
  final double black;
  final double wash;
  final Color washColor;

  /// UIKit's mask: a shadow of radius 18 (its spread, as a Gaussian's
  /// sigma, in points).
  static const double sigma = 18;

  /// The blur: a Gaussian of up to 1.72pt, in full where the mask is
  /// (UIKit's at rest; fitted on 8pt stripes).
  static const double blurSigma = 1.72;

  static final ShaderProgram _program = ShaderProgram('scroll_edge.frag');

  /// The mask at [d] points past the edge line into the bar: 0.5 on the
  /// line.
  static double mask(double d) {
    // The standard normal's distribution function (a tanh fit).
    final double z = d / sigma;
    return 0.5 * (1 + _tanh(0.7978846 * (z + 0.044715 * z * z * z)));
  }

  static double _tanh(double x) {
    final double e = math.exp(2 * x.clamp(-20.0, 20.0));
    return (e - 1) / (e + 1);
  }

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderScrollEdge(this)..configure(this, context);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderScrollEdge).configure(this, context);
  }
}

class _RenderScrollEdge extends RenderBox {
  _RenderScrollEdge(this._config);

  ScrollEdgeEffect _config;
  double _dpr = 1;
  ui.FragmentShader? _shader;
  final LayerHandle<ClipRectLayer> _clip = LayerHandle<ClipRectLayer>();
  final LayerHandle<BackdropFilterLayer> _filter =
      LayerHandle<BackdropFilterLayer>();

  void configure(ScrollEdgeEffect c, BuildContext context) {
    _config = c;
    _dpr = MediaQuery.devicePixelRatioOf(context);
    markNeedsPaint();
  }

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  bool hitTestSelf(Offset position) => false;

  bool get _showing =>
      _config.blur > 0.001 || _config.black > 0.001 || _config.wash > 0.001;

  @override
  bool get alwaysNeedsCompositing => _showing;

  @override
  void paint(PaintingContext context, Offset offset) {
    if (!_showing) {
      _clip.layer = null;
      _filter.layer = null;
      return;
    }
    final ScrollEdgeEffect c = _config;
    final ui.FragmentProgram? program = ScrollEdgeEffect._program.program;
    if (program == null) {
      ScrollEdgeEffect._program.load().then((_) {
        if (attached) {
          markNeedsPaint();
        }
      });
    }
    if (program == null || !ui.ImageFilter.isShaderFilterSupported) {
      _clip.layer = null;
      _filter.layer = null;
      _paintPlain(context.canvas, offset);
      return;
    }
    final ui.FragmentShader shader = _shader ??= program.fragmentShader();
    // The edge line in capture pixels (the screen's).
    final Matrix4 toRoot = getTransformTo(null);
    final Offset line = MatrixUtils.transformPoint(toRoot, Offset(0, c.edge));
    final double scale = MatrixUtils.transformRect(
      toRoot,
      const Rect.fromLTWH(0, 0, 0, 1),
    ).height;
    final double k = _dpr * scale;
    shader
      ..setFloat(2, line.dy * _dpr)
      ..setFloat(3, c.barAbove ? 1 : -1)
      ..setFloat(4, ScrollEdgeEffect.sigma * k)
      ..setFloat(5, ScrollEdgeEffect.blurSigma * k)
      ..setFloat(6, c.blur)
      ..setFloat(7, c.black)
      ..setFloat(8, c.wash)
      ..setFloat(9, 0)
      ..setFloat(10, c.washColor.r)
      ..setFloat(11, c.washColor.g)
      ..setFloat(12, c.washColor.b)
      ..setFloat(13, 1);
    _clip.layer = context.pushClipRect(true, offset, Offset.zero & size, (
      PaintingContext context,
      Offset offset,
    ) {
      final BackdropFilterLayer layer =
          (_filter.layer ??= BackdropFilterLayer())
            ..filter = ui.ImageFilter.shader(shader);
      context.pushLayer(
        layer,
        (PaintingContext context, Offset offset) {},
        offset,
      );
    }, oldLayer: _clip.layer);
  }

  // Where shader filters are not supported: the dim or the wash as a
  // gradient, without the blur.
  void _paintPlain(Canvas canvas, Offset offset) {
    final ScrollEdgeEffect c = _config;
    final Color tone = c.wash > c.black
        ? c.washColor.withValues(alpha: c.wash)
        : Color.fromRGBO(0, 0, 0, c.black);
    const int stops = 9;
    final List<double> at = <double>[];
    final List<Color> colors = <Color>[];
    for (var i = 0; i < stops; i++) {
      final double t = i / (stops - 1);
      final double y = t * size.height;
      final double d = c.barAbove ? c.edge - y : y - c.edge;
      at.add(t);
      colors.add(tone.withValues(alpha: tone.a * ScrollEdgeEffect.mask(d)));
    }
    final Rect rect = offset & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(
          rect.topCenter,
          rect.bottomCenter,
          colors,
          at,
        ),
    );
  }

  @override
  void dispose() {
    _clip.layer = null;
    _filter.layer = null;
    _shader?.dispose();
    super.dispose();
  }
}
