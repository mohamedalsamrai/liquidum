import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'glass_material.dart';

/// A rounded-rectangle surface made of [material], with [child] drawn on top.
///
/// The glass reads the pixels already painted behind it, so it must be painted
/// after the content it floats over (for example, later in a [Stack]).
///
/// Current limitations: the surface assumes it paints into the root layer (no
/// ancestor [Opacity], [ShaderMask] or similar save layer), and it refreshes
/// its geometry when it paints, so it should not sit under a [RepaintBoundary]
/// that moves without repainting it, such as inside a scrolling list.
class Glass extends SingleChildRenderObjectWidget {
  const Glass({
    super.key,
    this.material = GlassMaterial.regular,
    this.radius,
    super.child,
  });

  final GlassMaterial material;

  /// Corner radius. Null makes a capsule.
  final double? radius;

  /// Loads the glass shader ahead of the first frame that uses it.
  ///
  /// Optional: surfaces load it on demand and show a plain frost until then.
  static Future<void> precache() => _GlassProgram.load();

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderGlass(
      material: material,
      radius: radius,
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderGlass)
      ..material = material
      ..radius = radius
      ..devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
  }
}

class _RenderGlass extends RenderProxyBox {
  _RenderGlass({
    required this._material,
    this._radius,
    required this._devicePixelRatio,
    RenderBox? child,
  }) : super(child);

  GlassMaterial get material => _material;
  GlassMaterial _material;
  set material(GlassMaterial value) {
    if (value == _material) {
      return;
    }
    _material = value;
    markNeedsPaint();
  }

  double? get radius => _radius;
  double? _radius;
  set radius(double? value) {
    if (value == _radius) {
      return;
    }
    _radius = value;
    markNeedsPaint();
  }

  double get devicePixelRatio => _devicePixelRatio;
  double _devicePixelRatio;
  set devicePixelRatio(double value) {
    if (value == _devicePixelRatio) {
      return;
    }
    _devicePixelRatio = value;
    markNeedsPaint();
  }

  _GlassUniforms? _uniforms;
  final LayerHandle<ContainerLayer> _clipLayer = LayerHandle<ContainerLayer>();
  final LayerHandle<BackdropFilterLayer> _backdropLayer =
      LayerHandle<BackdropFilterLayer>();

  @override
  bool get alwaysNeedsCompositing => true;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    if (_GlassProgram.program == null) {
      _GlassProgram.load().then((_) {
        if (attached) {
          markNeedsPaint();
        }
      });
    }
  }

  @override
  void dispose() {
    _clipLayer.layer = null;
    _backdropLayer.layer = null;
    _uniforms?.shader.dispose();
    super.dispose();
  }

  double get _effectiveRadius {
    final double capsule = size.shortestSide / 2;
    return math.min(_radius ?? capsule, capsule);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final ui.FragmentProgram? program = _GlassProgram.program;
    if (size.isEmpty) {
      _clipLayer.layer = null;
    } else if (!ui.ImageFilter.isShaderFilterSupported) {
      _paintFrost(context, offset);
    } else if (program != null) {
      _paintGlass(context, offset, program);
    } else {
      // The shader is still loading; the surface appears once it is ready.
      _clipLayer.layer = null;
    }
    super.paint(context, offset);
  }

  void _paintGlass(
    PaintingContext context,
    Offset offset,
    ui.FragmentProgram program,
  ) {
    final GlassMaterial m = _material;
    final _GlassUniforms u = _uniforms ??= _GlassUniforms(
      program.fragmentShader(),
    );

    // The shader works in physical pixels of the root layer. Lengths scale by
    // the smaller axis, so a stretched surface keeps a round rim.
    final Rect global = MatrixUtils.transformRect(
      getTransformTo(null),
      Offset.zero & size,
    );
    final Rect pixels = Rect.fromLTRB(
      global.left * _devicePixelRatio,
      global.top * _devicePixelRatio,
      global.right * _devicePixelRatio,
      global.bottom * _devicePixelRatio,
    );
    final double toPixels = math.min(
      pixels.width / size.width,
      pixels.height / size.height,
    );
    final double capsule = pixels.shortestSide / 2;

    u.rect.set(
      pixels.center.dx,
      pixels.center.dy,
      pixels.width / 2,
      pixels.height / 2,
    );
    u.radius.set(math.min((_radius ?? capsule) * toPixels, capsule));
    u.refraction.set(m.refraction * toPixels);
    u.falloff.set(m.falloff * toPixels);
    u.ends.set(m.endRefraction * toPixels, m.endFalloff * toPixels);
    u.dispersion.set(m.dispersion);
    u.zoom.set(m.zoom);
    u.saturation.set(m.saturation);
    u.response.set(m.response);
    u.lift.set(m.lift);
    u.tint.set(m.tint.r, m.tint.g, m.tint.b, m.tint.a);
    u.light.set(math.cos(m.lightAngle), math.sin(m.lightAngle));
    u.specular.set(m.specular);
    u.rim.set(_rimWidth * toPixels);
    u.lightFocus.set(m.lightFocus);
    u.shadow.set(
      m.shadowOffset.dx * toPixels,
      m.shadowOffset.dy * toPixels,
      m.shadowSoftness * toPixels,
      m.shadowOpacity,
    );

    // Uniforms are copied when the filter is created, so make one per paint.
    ui.ImageFilter filter = ui.ImageFilter.shader(u.shader);
    if (m.blur > 0) {
      filter = ui.ImageFilter.compose(
        outer: filter,
        inner: ui.ImageFilter.blur(sigmaX: m.blur, sigmaY: m.blur),
      );
    }

    // Bound the pass to the shape plus its shadow; the shader draws the edge.
    final double reach = m.shadowSoftness * 3 + m.shadowOffset.distance + 1;
    _clipLayer.layer = context.pushClipRect(
      needsCompositing,
      offset,
      (Offset.zero & size).inflate(reach),
      _paintBackdrop(filter),
      oldLayer: switch (_clipLayer.layer) {
        final ClipRectLayer layer => layer,
        _ => null,
      },
    );
  }

  /// Blur and a flat veil, for backends without shader image filters.
  void _paintFrost(PaintingContext context, Offset offset) {
    final GlassMaterial m = _material;
    final RRect shape = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(_effectiveRadius),
    );
    _clipLayer.layer = context.pushClipRRect(
      needsCompositing,
      offset,
      Offset.zero & size,
      shape,
      _paintBackdrop(
        ui.ImageFilter.blur(sigmaX: m.blur * 2, sigmaY: m.blur * 2),
        veil: Color.fromRGBO(255, 255, 255, m.lift),
      ),
      oldLayer: switch (_clipLayer.layer) {
        final ClipRRectLayer layer => layer,
        _ => null,
      },
    );
  }

  PaintingContextCallback _paintBackdrop(ui.ImageFilter filter, {Color? veil}) {
    return (PaintingContext context, Offset offset) {
      final BackdropFilterLayer layer =
          (_backdropLayer.layer ??= BackdropFilterLayer())..filter = filter;
      context.pushLayer(layer, (PaintingContext context, Offset offset) {
        if (veil != null) {
          context.canvas.drawRect(offset & size, Paint()..color = veil);
        }
      }, offset);
    };
  }
}

/// Width of the rim light, as measured on iOS 26.
const double _rimWidth = 1.25;

/// Named bindings into one surface's instance of the glass shader.
class _GlassUniforms {
  _GlassUniforms(this.shader)
    : rect = shader.getUniformVec4('uRect'),
      radius = shader.getUniformFloat('uRadius'),
      refraction = shader.getUniformFloat('uRefraction'),
      falloff = shader.getUniformFloat('uFalloff'),
      ends = shader.getUniformVec2('uEnds'),
      dispersion = shader.getUniformFloat('uDispersion'),
      zoom = shader.getUniformFloat('uZoom'),
      saturation = shader.getUniformFloat('uSaturation'),
      response = shader.getUniformFloat('uResponse'),
      lift = shader.getUniformFloat('uLift'),
      tint = shader.getUniformVec4('uTint'),
      light = shader.getUniformVec2('uLight'),
      specular = shader.getUniformFloat('uSpecular'),
      rim = shader.getUniformFloat('uRim'),
      lightFocus = shader.getUniformFloat('uLightFocus'),
      shadow = shader.getUniformVec4('uShadow');

  final ui.FragmentShader shader;
  final ui.UniformVec4Slot rect;
  final ui.UniformFloatSlot radius;
  final ui.UniformFloatSlot refraction;
  final ui.UniformFloatSlot falloff;
  final ui.UniformVec2Slot ends;
  final ui.UniformFloatSlot dispersion;
  final ui.UniformFloatSlot zoom;
  final ui.UniformFloatSlot saturation;
  final ui.UniformFloatSlot response;
  final ui.UniformFloatSlot lift;
  final ui.UniformVec4Slot tint;
  final ui.UniformVec2Slot light;
  final ui.UniformFloatSlot specular;
  final ui.UniformFloatSlot rim;
  final ui.UniformFloatSlot lightFocus;
  final ui.UniformVec4Slot shadow;
}

/// The glass shader, loaded once and shared by every surface.
abstract final class _GlassProgram {
  static ui.FragmentProgram? program;
  static Future<void>? _loading;

  static Future<void> load() => _loading ??= _load();

  static Future<void> _load() async {
    // The first key is how apps see the asset; the second is how this package
    // sees it when it is the app, as in its own tests.
    const keys = <String>[
      'packages/liquidum/shaders/glass.frag',
      'shaders/glass.frag',
    ];
    Object? error;
    StackTrace? stack;
    for (final key in keys) {
      try {
        program = await ui.FragmentProgram.fromAsset(key);
        return;
      } catch (e, s) {
        error ??= e;
        stack ??= s;
      }
    }
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error!,
        stack: stack,
        library: 'liquidum',
        context: ErrorDescription('while loading the glass shader'),
      ),
    );
  }
}
