import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'frame_sampler.dart';
import 'glass_backdrop.dart';
import 'shader_program.dart';
import 'tab_bar/appearance.dart';
import 'tab_bar/tint.dart';

/// UIKit's styles of glass (`UIGlassEffect.Style`).
enum GlassStyle {
  /// Frosted glass, for bars, controls and anything with content on it.
  regular,

  /// Clearer, more refractive glass with no shadow, for glass over rich
  /// content such as photos and video.
  clear,
}

/// UIKit's glass (`UIGlassEffect`) behind [child], in a box with rounded
/// corners: a capsule unless [radius] says otherwise.
///
/// The glass is the tab bar's: it frosts what is behind it, refracts it
/// near its edge, lights its rim and casts a soft shadow, with the inputs
/// UIKit gives glass of this size and style (measured on iOS 26.5). Up to
/// 64pt in its short side it turns light or dark with what is behind it, as
/// UIKit's does, when that is wrapped in a [GlassBackdrop]; larger glass
/// follows the system's appearance.
///
/// Paint it after the content it floats over (for example later in a
/// [Stack]), and not inside an [Opacity], a [ShaderMask] or another save
/// layer: it reads the pixels already painted behind it.
class Glass extends StatefulWidget {
  const Glass({
    super.key,
    this.style = GlassStyle.regular,
    this.radius,
    this.tint,
    this.brightness,
    this.child,
  });

  final GlassStyle style;

  /// The corners' radius. A capsule (half the short side) when null.
  final double? radius;

  /// Tints the glass, as `UIGlassEffect.tintColor`: the glass takes the
  /// color, deeper where it is darker. The color's alpha sets how strongly.
  final Color? tint;

  /// Forces the light or the dark appearance. By default small glass follows
  /// what is behind it, and large glass the system.
  final Brightness? brightness;

  final Widget? child;

  static final ShaderProgram _program = ShaderProgram('glass.frag');

  /// Loads the glass shader ahead of time. Optional: glass loads it itself,
  /// and appears once it is in.
  static Future<void> precache() => _program.load();

  @override
  State<Glass> createState() => _GlassState();
}

class _GlassState extends State<Glass> with SingleTickerProviderStateMixin {
  final GlassAppearance _appearance = GlassAppearance();
  late final Ticker _ticker = createTicker(_tick);
  late final FrameSampler _sampler;
  final _Repaint _repaint = _Repaint();
  bool _sampling = false;

  @override
  void initState() {
    super.initState();
    _sampler = FrameSampler(
      interval: const Duration(milliseconds: 50),
      sample: _sample,
    );
    Glass._program.load().then((_) {
      if (mounted) {
        _repaint.notify();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _configure();
  }

  @override
  void didUpdateWidget(Glass oldWidget) {
    super.didUpdateWidget(oldWidget);
    _configure();
  }

  void _configure() {
    final Brightness? forced = widget.brightness;
    _appearance
      ..adaptive = forced == null
      ..system = forced ?? MediaQuery.platformBrightnessOf(context);
    _wake();
  }

  void _tick(Duration _) {
    final double now =
        SchedulerBinding.instance.currentSystemFrameTimeStamp.inMicroseconds /
        1e6;
    if (!_appearance.tick(now)) {
      _ticker.stop();
    }
    _repaint.notify();
  }

  void _wake() {
    if (!_ticker.isActive) {
      _ticker.start();
    }
  }

  // Reads the backdrop under small glass, as the bar does; large glass and
  // clear glass do not follow it.
  Future<void> _sample() async {
    if (_sampling ||
        !mounted ||
        _appearance.isLarge ||
        widget.style == GlassStyle.clear) {
      return;
    }
    final RenderObject? box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) {
      return;
    }
    final Rect rect = MatrixUtils.transformRect(
      box.getTransformTo(null),
      Offset.zero & box.size,
    );
    final GlassBackdropState? backdrop = glassBackdropUnder(rect);
    if (backdrop == null) {
      return;
    }
    _sampling = true;
    try {
      final double? luma = await backdrop.meanLuma(
        GlassAppearance.glassSampleArea(rect),
      );
      if (mounted && luma != null && !_appearance.wouldKeep(luma)) {
        _appearance.sample(luma);
        _wake();
      }
    } finally {
      _sampling = false;
    }
  }

  @override
  void dispose() {
    _sampler.dispose();
    _ticker.dispose();
    _repaint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _GlassSurface(
      style: widget.style,
      radius: widget.radius,
      tint: widget.tint,
      appearance: _appearance,
      repaint: _repaint,
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
      child: widget.child,
    );
  }
}

class _Repaint extends ChangeNotifier {
  void notify() => notifyListeners();
}

class _GlassSurface extends SingleChildRenderObjectWidget {
  const _GlassSurface({
    required this.style,
    required this.radius,
    required this.tint,
    required this.appearance,
    required this.repaint,
    required this.devicePixelRatio,
    super.child,
  });

  final GlassStyle style;
  final double? radius;
  final Color? tint;
  final GlassAppearance appearance;
  final Listenable repaint;
  final double devicePixelRatio;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderGlass(
    style: style,
    radius: radius,
    tint: tint,
    appearance: appearance,
    repaint: repaint,
    devicePixelRatio: devicePixelRatio,
  );

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderGlass)
      ..style = style
      ..radius = radius
      ..tint = tint
      ..repaint = repaint
      ..devicePixelRatio = devicePixelRatio;
  }
}

/// UIKit's inputs for glass of a size and style, by its short side h
/// (points), as its glass filter sets them (iOS 26.5).
class _GlassOptics {
  _GlassOptics(double h, GlassStyle style)
    : clear = style == GlassStyle.clear,
      inner = style == GlassStyle.clear
          ? math.min(h, 60)
          : math.min(0.8 * h, 60),
      innerHeight = style == GlassStyle.clear
          ? math.min(0.36 * h, 20)
          : math.min(0.25 * h, 20),
      frostDepth = math.max(h / 2, 1.5),
      heavySigma = style == GlassStyle.clear
          ? _clearHeavySigma
          : _heavySigma62 * _byHeight(h, _heavyScale),
      lightSigma = style == GlassStyle.clear
          ? _clearLightSigma
          : h <= 62
          ? _lightSigma62
          : math.sqrt(
              math.pow(_byHeight(h, _lightFit), 2) -
                  _lightFit62 * _lightFit62 +
                  _lightSigma62 * _lightSigma62,
            ),
      frostRamp = style == GlassStyle.clear
          ? _clearRamp
          : _ramp62 * _byHeight(h, _rampScale);

  final bool clear;

  /// The inward refraction at the edge and the depth it reaches (points).
  final double inner;
  final double innerHeight;

  /// How deep the frost reaches its full blur: the middle line.
  final double frostDepth;

  /// The frost: the heavy blur's sigma and the light one's (points), and
  /// the power along which the light one fades with depth. The bar's at
  /// 62pt (fitted to UIKit's frost there), scaled by height as UIKit's
  /// frost alone scales over stripes (iOS 26.5): blurrier, and fading
  /// sooner, past 64pt. Clear glass's heavy blur: UIKit's blur radius 1
  /// against 5/3 at 62pt.
  final double heavySigma;
  final double lightSigma;
  final double frostRamp;

  static const double _heavySigma62 = 2.9;

  // Clear glass's frost, the same at every height: UIKit's clear frost alone
  // blurs 1.67pt (asked of Impeller as 1.88, which blurs less than asked
  // below 3), and its light blur and ramp, against regular glass's at 62pt,
  // scale the bar's by 0.60 / 0.93 and 1.92 / 1.06.
  static const double _clearHeavySigma = 1.88;
  static const double _clearLightSigma = 0.30;
  static const double _clearRamp = 1.30;
  static const double _lightSigma62 = 0.46;
  static const double _ramp62 = 0.72;

  // (height, factor) on the 62pt values, from fits of UIKit's frost alone.
  static const List<(double, double)> _heavyScale = <(double, double)>[
    (62, 1),
    (64, 1.054),
    (66, 1.11),
    (70, 1.23),
    (80, 1.46),
    (90, 1.40),
    (160, 3.51),
  ];
  // UIKit's light frost alone (points, fitted over stripes): what it adds
  // to the bar's at 62pt is added here, in quadrature.
  static const double _lightFit62 = 0.93;
  static const List<(double, double)> _lightFit = <(double, double)>[
    (62, 0.93),
    (64, 0.95),
    (66, 0.97),
    (70, 1.00),
    (80, 1.15),
    (90, 1.36),
    (160, 2.66),
  ];
  static const List<(double, double)> _rampScale = <(double, double)>[
    (62, 1),
    (66, 0.97),
    (70, 0.88),
    (80, 0.64),
    (90, 0.48),
    (160, 0.40),
  ];

  // A table's value at height h: linear between its points, and from 160pt
  // on its last, as UIKit's inputs stop growing there.
  static double _byHeight(double h, List<(double, double)> table) {
    final (double h0, double f0) = table.first;
    final (double hn, double fn) = table.last;
    if (h <= 62) {
      // The bar's own fit holds below: only the heavy blur follows the
      // blur radius.
      return identical(table, _heavyScale)
          ? math.max(4 / 3, _radius(h)) / _radius(62)
          : 1;
    }
    if (h <= h0) {
      return f0;
    }
    if (h >= hn) {
      return fn;
    }
    for (var i = 1; i < table.length; i++) {
      final (double a, double fa) = table[i - 1];
      final (double b, double fb) = table[i];
      if (h <= b) {
        return fa + (fb - fa) * (h - a) / (b - a);
      }
    }
    return fn;
  }

  // UIKit's frost blur radius for glass h points tall.
  static double _radius(double h) => (h / 2 + 4) / 21;

  // The shadow (points): offset, sigma, center and reach, as the bar's.
  static const double shadowOffset = 8;
  static const double shadowSigma = 16.4;
  static const double shadowCenter = 0.85;
  static const double shadowReach = 39.06;

  // The rim's curvature, as the bar's platter's.
  static const double rimCurvature = 0.7;

  // Clear glass's face: fixed, whatever is behind it.
  static const (double, double, double, double) clearFace = (0.075, 1.15, 0, 1);
  static const double clearChroma = 1.06;

  /// How much of large glass's bleed shows: none up to 64pt, then more with
  /// its height, faster in the dark appearance (UIKit's).
  /// (UIKit's stops growing at 160pt: half, or 0.8 dark.)
  static double bleedOpacity(double h, {required bool dark}) =>
      ((math.min(h, 160) - 64) / (dark ? 120 : 192)).clamp(0.0, 1.0);

  // The bleed's color, from the glass's (rows: to red, green, blue; columns:
  // from red, green, blue, and 1). Fitted to UIKit's bleed layer over color
  // blocks (iOS 26.5) at 100 to 400pt: within 2 to 4 levels of its glass
  // in light, 1 to 2 in dark (3.7 at 160pt). UIKit computes it otherwise,
  // from inputs not modeled yet.
  static const List<List<double>> bleedLight = <List<double>>[
    <double>[0.565, 0.367, 0.141, -0.003],
    <double>[0.188, 0.704, 0.138, 0.006],
    <double>[0.176, 0.275, 0.471, 0.119],
  ];
  static const List<List<double>> bleedDark = <List<double>>[
    <double>[0.787, 0.083, 0.037, 0.034],
    <double>[0.062, 0.861, 0.049, 0.022],
    <double>[0.069, 0.139, 0.792, 0.001],
  ];
}

class _RenderGlass extends RenderProxyBox {
  _RenderGlass({
    required this._style,
    required this._radius,
    required this._tint,
    required this.appearance,
    required this._repaint,
    required this._devicePixelRatio,
  });

  final GlassAppearance appearance;

  GlassStyle get style => _style;
  GlassStyle _style;
  set style(GlassStyle value) {
    if (value != _style) {
      _style = value;
      markNeedsPaint();
    }
  }

  double? get radius => _radius;
  double? _radius;
  set radius(double? value) {
    if (value != _radius) {
      _radius = value;
      markNeedsPaint();
    }
  }

  Color? get tint => _tint;
  Color? _tint;
  set tint(Color? value) {
    if (value != _tint) {
      _tint = value;
      markNeedsPaint();
    }
  }

  Listenable get repaint => _repaint;
  Listenable _repaint;
  set repaint(Listenable value) {
    if (value == _repaint) {
      return;
    }
    if (attached) {
      _repaint.removeListener(markNeedsPaint);
      value.addListener(markNeedsPaint);
    }
    _repaint = value;
  }

  double get devicePixelRatio => _devicePixelRatio;
  double _devicePixelRatio;
  set devicePixelRatio(double value) {
    if (value != _devicePixelRatio) {
      _devicePixelRatio = value;
      markNeedsPaint();
    }
  }

  // One shader per pass: a shader image filter reads its uniforms only when
  // it is composited.
  _GlassUniforms? _glassPass;
  _GlassUniforms? _frostPass;

  final LayerHandle<ClipRRectLayer> _frostClip = LayerHandle<ClipRRectLayer>();
  final LayerHandle<BackdropFilterLayer> _frostHeavy =
      LayerHandle<BackdropFilterLayer>();
  final LayerHandle<BackdropFilterLayer> _frostLight =
      LayerHandle<BackdropFilterLayer>();
  final LayerHandle<ClipRectLayer> _glassClip = LayerHandle<ClipRectLayer>();
  final LayerHandle<BackdropFilterLayer> _glassLayer =
      LayerHandle<BackdropFilterLayer>();
  final BackdropKey _frostCapture = BackdropKey();

  @override
  bool get alwaysNeedsCompositing => true;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _repaint.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _repaint.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void dispose() {
    _clearLayers();
    _glassPass?.shader.dispose();
    _frostPass?.shader.dispose();
    super.dispose();
  }

  void _clearLayers() {
    _frostClip.layer = null;
    _frostHeavy.layer = null;
    _frostLight.layer = null;
    _glassClip.layer = null;
    _glassLayer.layer = null;
  }

  @override
  void performLayout() {
    super.performLayout();
    appearance.height = size.shortestSide;
  }

  double get _cornerRadius {
    final double capsule = size.shortestSide / 2;
    return math.min(_radius ?? capsule, capsule);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final ui.FragmentProgram? program = Glass._program.program;
    if (size.isEmpty || program == null) {
      _clearLayers();
    } else if (!ui.ImageFilter.isShaderFilterSupported) {
      _paintPlain(context, offset);
    } else {
      _paintGlass(context, offset, program);
    }
    super.paint(context, offset);
  }

  // Without shader filters: a plain frost.
  void _paintPlain(PaintingContext context, Offset offset) {
    _frostLight.layer = null;
    _glassClip.layer = null;
    _glassLayer.layer = null;
    final RRect shape = RRect.fromRectAndRadius(
      offset & size,
      Radius.circular(_cornerRadius),
    );
    _frostClip.layer = context.pushClipRRect(
      needsCompositing,
      Offset.zero,
      shape.outerRect,
      shape,
      (PaintingContext context, Offset _) {
        final BackdropFilterLayer layer =
            (_frostHeavy.layer ??= BackdropFilterLayer())
              ..filter = ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8);
        context.pushLayer(layer, (PaintingContext context, Offset _) {
          context.canvas.drawRRect(
            shape,
            Paint()
              ..color = appearance.isDark
                  ? const Color(0x99202024)
                  : const Color(0x99F2F2F7),
          );
        }, Offset.zero);
      },
      oldLayer: _frostClip.layer,
    );
  }

  void _paintGlass(
    PaintingContext context,
    Offset offset,
    ui.FragmentProgram program,
  ) {
    final _GlassUniforms glassPass = _glassPass ??= _GlassUniforms(
      program.fragmentShader(),
    );
    final _GlassUniforms frostPass = _frostPass ??= _GlassUniforms(
      program.fragmentShader(),
    );
    // The capture's pixels: physical pixels of the pass the backdrop is
    // captured from.
    final Matrix4 toRoot = getTransformTo(null);
    final double k =
        _devicePixelRatio *
        (MatrixUtils.transformPoint(toRoot, const Offset(1, 0)) -
                MatrixUtils.transformPoint(toRoot, Offset.zero))
            .distance;
    final Rect global = MatrixUtils.transformRect(toRoot, Offset.zero & size);
    final Rect pixels = Rect.fromLTRB(
      global.left * _devicePixelRatio,
      global.top * _devicePixelRatio,
      global.right * _devicePixelRatio,
      global.bottom * _devicePixelRatio,
    );
    final double h = size.shortestSide;
    final double r = _cornerRadius;
    final optics = _GlassOptics(h, _style);
    final bool clear = optics.clear;
    final (double, double, double, double) face = clear
        ? _GlassOptics.clearFace
        : appearance.face;
    final (double, double, double) rim = appearance.platterRim;
    final GlassTint tint = GlassTint(_tint, darkAppearance: appearance.isDark);

    void set(_GlassUniforms u, double pass) {
      u
        ..shape.set(
          pixels.center.dx,
          pixels.center.dy,
          pixels.width / 2,
          pixels.height / 2,
        )
        // UIKit's glass filter refracts along its shape's distance gradient
        // (no ovalization, unlike the lens's warp).
        ..pass.set(pass, k, r * k, 0)
        ..optics.set(optics.inner, optics.innerHeight, 0, appearance.refraction)
        ..frost.set(optics.frostDepth, optics.lightSigma, optics.frostRamp, 0)
        ..face.set(face.$1, face.$2, face.$3, face.$4)
        ..rim.set(rim.$1, rim.$2, rim.$3, clear ? 0 : appearance.shadow)
        ..shadow.set(
          _GlassOptics.shadowOffset,
          _GlassOptics.shadowSigma,
          _GlassOptics.shadowCenter,
          _GlassOptics.shadowReach,
        )
        ..more.set(
          clear ? _GlassOptics.clearChroma : appearance.chroma,
          0,
          _GlassOptics.rimCurvature,
          0,
        )
        ..glow.set(0, 0, 0, 0)
        ..setTint(tint)
        ..setBleed(
          appearance.isDark ? _GlassOptics.bleedDark : _GlassOptics.bleedLight,
          clear ? 0 : _GlassOptics.bleedOpacity(h, dark: appearance.isDark),
        );
    }

    set(frostPass, 1);
    set(glassPass, 0);

    // The frost, into the backdrop where the glass covers it: a heavy blur,
    // and the shader's light one over it, both from the backdrop as it was.
    final double inset = _GlassFrost.inset / _devicePixelRatio;
    final RRect frostShape = RRect.fromRectAndRadius(
      (offset & size).deflate(inset),
      Radius.circular(math.max(r - inset, 0)),
    );
    final double sigma = optics.heavySigma * k / _devicePixelRatio;
    final BackdropFilterLayer heavy =
        (_frostHeavy.layer ??= BackdropFilterLayer())
          ..filter = ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma)
          ..backdropKey = _frostCapture;
    final BackdropFilterLayer light =
        (_frostLight.layer ??= BackdropFilterLayer())
          ..filter = ui.ImageFilter.shader(frostPass.shader)
          ..backdropKey = _frostCapture;
    _frostClip.layer = context.pushClipRRect(
      needsCompositing,
      Offset.zero,
      frostShape.outerRect,
      frostShape,
      (PaintingContext context, Offset _) {
        context
          ..pushLayer(heavy, _paintNothing, Offset.zero)
          ..pushLayer(light, _paintNothing, Offset.zero);
      },
      oldLayer: _frostClip.layer,
    );

    // The glass, over its frost, and its shadow around it.
    _glassClip.layer = context.pushClipRect(
      needsCompositing,
      Offset.zero,
      (offset & size).inflate(clear ? 2 : _GlassOptics.shadowReach + 2),
      (PaintingContext context, Offset _) {
        final BackdropFilterLayer layer =
            (_glassLayer.layer ??= BackdropFilterLayer())
              ..filter = ui.ImageFilter.shader(glassPass.shader);
        context.pushLayer(layer, _paintNothing, Offset.zero);
      },
      oldLayer: _glassClip.layer,
    );
  }

  static void _paintNothing(PaintingContext context, Offset offset) {}
}

abstract final class _GlassFrost {
  // The frost lies within the glass by this many pixels (the shader's
  // kFrostInset), under glass drawn opaque.
  static const double inset = 2;
}

/// Named bindings into the glass shader.
class _GlassUniforms {
  _GlassUniforms(this.shader)
    : shape = shader.getUniformVec4('uShape'),
      pass = shader.getUniformVec4('uPass'),
      optics = shader.getUniformVec4('uOptics'),
      face = shader.getUniformVec4('uFace'),
      rim = shader.getUniformVec4('uRim'),
      shadow = shader.getUniformVec4('uShadow'),
      more = shader.getUniformVec4('uMore'),
      frost = shader.getUniformVec4('uFrost'),
      glow = shader.getUniformVec4('uGlow'),
      tints = shader.getUniformVec4Array('uTints'),
      bleed = shader.getUniformVec4Array('uBleed');

  final ui.FragmentShader shader;
  final ui.UniformVec4Slot shape;
  final ui.UniformVec4Slot pass;
  final ui.UniformVec4Slot optics;
  final ui.UniformVec4Slot face;
  final ui.UniformVec4Slot rim;
  final ui.UniformVec4Slot shadow;
  final ui.UniformVec4Slot more;
  final ui.UniformVec4Slot frost;
  final ui.UniformVec4Slot glow;
  final ui.UniformArray<ui.UniformVec4Slot> tints;
  final ui.UniformArray<ui.UniformVec4Slot> bleed;

  void setBleed(List<List<double>> matrix, double opacity) {
    for (var i = 0; i < 3; i++) {
      bleed[i].set(matrix[i][0], matrix[i][1], matrix[i][2], matrix[i][3]);
    }
    bleed[3].set(opacity, 0, 0, 0);
  }

  /// One color for the whole glass (no gradient).
  void setTint(GlassTint t) {
    tints[0].set(t.bright[0], t.bright[1], t.bright[2], t.alpha);
    tints[1].set(t.dark[0], t.dark[1], t.dark[2], 0);
    tints[2].set(t.bright[0], t.bright[1], t.bright[2], t.alpha);
    tints[3].set(t.dark[0], t.dark[1], t.dark[2], 0);
    tints[4].set(0, 0, 0, 0);
  }
}
