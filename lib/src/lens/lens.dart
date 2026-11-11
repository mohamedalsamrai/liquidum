/// UIKit's liquid lens (`_UILiquidLensView`) on its own, for the controls
/// built on it (the switch's and the slider's thumb, the segmented control's
/// selection). Internal: nothing here is exported.
///
/// The contract, for a control:
///
/// - Build a [LiquidLens] around the control's content (the track, its
///   labels, anything the lens floats over), and give it the thumb's [rect]
///   in that content's coordinates, in points. The lens is a capsule (half
///   the short side rounded), as UIKit's thumbs and selections are; other
///   corners are not supported yet. The child is painted first, as it is,
///   and the lens reads it (and whatever lies behind the control) from the
///   pixels, so the track and the labels under the lens are what it warps
///   and refracts. Do not paint the thumb yourself: the lens is the thumb.
/// - Drive [lift] from 0 (the resting pill: what is behind, blurred, under
///   the resting matrix or the [indicator]'s color) to 1 (the lifted clear
///   lens, with its rim, shadow and [decoration]), with a [LensLift] ticked
///   on the frame clock: `down()` on a touch, `up()` when it leaves, and
///   `lift` and `growth` from it each frame. Grow [rect] with `growth` as
///   the control's lens grows (the bar's by 8pt a side); the lens draws
///   [rect] as given.
/// - A drag's stretch and drift are the control's: pass them as [flexScale]
///   (about the rect's center) and [drift]; the lens scales its optics with
///   the flex as the bar's does.
/// - Paint the lens after the content it floats over, and not inside an
///   [Opacity], a [ShaderMask] or another save layer: it reads the pixels
///   already painted behind it. Several lenses or glass over one capture
///   may share a [backdropKey].
/// - The lens's colors follow a [GlassAppearance]: pass the control's
///   (ticked by the control) or none, for one at the ambient brightness
///   that does not adapt to the backdrop.
///
/// What differs from the tab bar's lens: no platter lies under it, and it
/// lifts no content of its own (the bar renders its selected tabs into an
/// atlas and lenses them by UIKit's content displacement, 17.5pt and 16%
/// growth); anything under this lens is backdrop, warped by up to 9pt and
/// refracted 17.5pt deep as a backdrop is. Whether UIKit's segmented
/// control lenses its selected label as content is for the controls'
/// research to settle.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../shader_program.dart';
import '../tab_bar/appearance.dart';
import '../tab_bar/decoration.dart';
import '../tab_bar/decoration_paint.dart';

export '../tab_bar/decoration.dart' show GlassDecoration, GlassFill;
export 'lens_flex.dart' show LensFlex;
export 'lens_physics.dart' show LensLift, LensVariant;

/// A liquid lens's own optical inputs (its glass filter's, iOS 26.5):
/// UIKit scales its large lens's by the lens's lifted height, and gives
/// its small lens (the switch's and the slider's thumbs) inputs of its own.
@immutable
class LensOptics {
  const LensOptics({
    required this.inner,
    required this.innerHeight,
    this.blur = 0,
    this.shadow = barShadow,
    this.faceBlack = 0,
    this.rim = 1,
  });

  /// The large lens, [liftedHeight] points tall when lifted (the tab bar's
  /// lens: 70pt; a segmented control's selection: 44): inner refraction a
  /// quarter of the height, a tenth deep, the bar's shadow.
  const LensOptics.large(double liftedHeight)
    : this(inner: liftedHeight / 4, innerHeight: liftedHeight / 10);

  /// The small lens, [liftedHeight] points tall (the switch's thumb: 38.33;
  /// the slider's: 37): inner refraction half the height, 0.18 of it deep,
  /// a blur of radius 2 over what it reads, its face's black point lifted
  /// to 0.1, its shadow at 0.18 against the large lens's 0.1. Its highlight
  /// is UIKit's glass highlight (amount 0.25) rather than the large lens's
  /// key/fill lighting: drawn here as the bar's rim, to settle against
  /// UIKit.
  const LensOptics.small(double liftedHeight)
    : this(
        inner: liftedHeight / 2,
        innerHeight: 0.18 * liftedHeight,
        // UIKit's blur radius 2 and face black point 0.1 are inputs of its
        // glass filter that do not show in the lifted thumb's middle (its
        // backdrop is as sharp and as deep as around it, iOS 26.5): none
        // here, and the rim at half strength (UIKit's highlight 0.25 is
        // fainter than the large lens's lighting).
        blur: 0,
        shadow: barShadow * 1.8,
        faceBlack: 0,
        rim: 0.5,
      );

  /// The tab bar's lens: its inputs as lens_material.glsl has them.
  static const LensOptics bar = LensOptics(inner: 17.5, innerHeight: 7);

  /// The bar's lens's shadow strength (lens_material.glsl).
  static const double barShadow = 0.1086;

  /// The small lens's blur (sigma, points) for UIKit's blur radius 2 (as
  /// the glass's frost: 1.74 sigma per unit of radius). UIKit iOS 26.5, to
  /// confirm.
  static const double smallBlur = 3.5;

  /// The inner refraction's amount and how deep it reaches (points).
  final double inner;
  final double innerHeight;

  /// A gaussian blur (sigma, points) of what the lifted lens reads; none
  /// at 0.
  final double blur;

  /// The shadow's strength around the lifted lens.
  final double shadow;

  /// The face's black point: what the lifted lens reads is lifted toward
  /// white by this much.
  final double faceBlack;

  /// How strongly the rim is lit, 1 being the bar's.
  final double rim;

  @override
  bool operator ==(Object other) =>
      other is LensOptics &&
      other.inner == inner &&
      other.innerHeight == innerHeight &&
      other.blur == blur &&
      other.shadow == shadow &&
      other.faceBlack == faceBlack &&
      other.rim == rim;

  @override
  int get hashCode =>
      Object.hash(inner, innerHeight, blur, shadow, faceBlack, rim);
}

/// The liquid lens over [child], at [rect] (see the library's contract).
class LiquidLens extends SingleChildRenderObjectWidget {
  const LiquidLens({
    super.key,
    required this.rect,
    this.lift = 0,
    this.flexScale = const Size(1, 1),
    this.drift = Offset.zero,
    this.indicator = const GlassDecoration(),
    this.decoration = const GlassDecoration(),
    this.optics = LensOptics.bar,
    this.appearance,
    this.opacity = 1,
    this.backdropKey,
    this.stages = allStages,
    super.child,
  });

  /// The lens's bounds in [child]'s coordinates (points), before its flex:
  /// a capsule. Null when a parent render object places the lens itself,
  /// setting [RenderLiquidLens.rect] in its layout (as the segmented
  /// control's box does: its segments' width is only known then).
  final Rect? rect;

  /// The lift progress, 0 (the resting pill) to 1 (the lifted lens).
  final double lift;

  /// The lens's flex: a scale about [rect]'s center (the tab bar's lens
  /// stretches along a drag, keeping its area) and a shift.
  final Size flexScale;
  final Offset drift;

  /// The resting pill's decoration, and the lifted lens's (as the tab bar's
  /// `indicator` and `lens`): a color or gradient, tinted or painted, and
  /// shadows around and inside the shape.
  final GlassDecoration indicator;
  final GlassDecoration decoration;

  /// The lens's own optical inputs: the bar's by default.
  final LensOptics optics;

  /// The appearance the lens's colors follow. None: the ambient brightness,
  /// not adapting to the backdrop.
  final GlassAppearance? appearance;

  /// How much the lens shows, 0 to 1 (the whole of it, its shadow included).
  final double opacity;

  /// The capture the lens reads: its own, unless shared.
  final BackdropKey? backdropKey;

  /// The lens's optical stages, as a bit mask (the tab bar's
  /// `GlassTabBarOptics`): all by default; for comparisons.
  final int stages;

  static const int allStages = 511;

  static final ShaderProgram _program = ShaderProgram('lens.frag');

  /// Loads the lens shader ahead of time. Optional: the lens loads it
  /// itself, and appears once it is in.
  static Future<void> precache() => _program.load();

  @override
  RenderObject createRenderObject(BuildContext context) => RenderLiquidLens(
    rect: rect ?? Rect.zero,
    lift: lift,
    flexScale: flexScale,
    drift: drift,
    indicator: indicator,
    decoration: decoration,
    optics: optics,
    appearance: appearance,
    opacity: opacity,
    backdropKey: backdropKey,
    stages: stages,
    brightness:
        MediaQuery.maybePlatformBrightnessOf(context) ?? Brightness.light,
    textDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
    devicePixelRatio: MediaQuery.maybeDevicePixelRatioOf(context) ?? 1,
  );

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    final RenderLiquidLens lens = renderObject as RenderLiquidLens;
    if (rect case final Rect rect) {
      lens.rect = rect;
    }
    lens
      ..lift = lift
      ..flexScale = flexScale
      ..drift = drift
      ..indicator = indicator
      ..decoration = decoration
      ..optics = optics
      ..appearance = appearance
      ..opacity = opacity
      ..backdropKey = backdropKey
      ..stages = stages
      ..brightness =
          MediaQuery.maybePlatformBrightnessOf(context) ?? Brightness.light
      ..textDirection = Directionality.maybeOf(context) ?? TextDirection.ltr
      ..devicePixelRatio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
  }
}

/// Paints its child, then the liquid lens over it.
class RenderLiquidLens extends RenderProxyBox {
  RenderLiquidLens({
    required Rect rect,
    required double lift,
    required Size flexScale,
    required Offset drift,
    required GlassDecoration indicator,
    required GlassDecoration decoration,
    required LensOptics optics,
    required GlassAppearance? appearance,
    required double opacity,
    required BackdropKey? backdropKey,
    required int stages,
    required Brightness brightness,
    required TextDirection textDirection,
    required double devicePixelRatio,
  }) : this._(
         rect,
         lift,
         flexScale,
         drift,
         indicator,
         decoration,
         optics,
         appearance,
         opacity,
         backdropKey,
         stages,
         brightness,
         textDirection,
         devicePixelRatio,
       );

  RenderLiquidLens._(
    this._rect,
    this._lift,
    this._flexScale,
    this._drift,
    this._indicator,
    this._decoration,
    this._optics,
    this._appearance,
    this._opacity,
    this._backdropKey,
    this._stages,
    this._brightness,
    this._textDirection,
    this._devicePixelRatio,
  );

  // The ovalization of UIKit's glass shapes, for the lens's distance field
  // (the tab bar's).
  static const double _ovalization = 0.5;

  // How far the lens's shadow reaches past it: its outline moved 7pt down,
  // and 9.2pt past that (the tab bar's).
  static const double _shadowMargin = 18;

  Rect get rect => _rect;
  Rect _rect;
  set rect(Rect value) {
    if (value != _rect) {
      _rect = value;
      markNeedsPaint();
    }
  }

  double get lift => _lift;
  double _lift;
  set lift(double value) {
    if (value != _lift) {
      _lift = value;
      markNeedsPaint();
    }
  }

  Size get flexScale => _flexScale;
  Size _flexScale;
  set flexScale(Size value) {
    if (value != _flexScale) {
      _flexScale = value;
      markNeedsPaint();
    }
  }

  Offset get drift => _drift;
  Offset _drift;
  set drift(Offset value) {
    if (value != _drift) {
      _drift = value;
      markNeedsPaint();
    }
  }

  GlassDecoration get indicator => _indicator;
  GlassDecoration _indicator;
  set indicator(GlassDecoration value) {
    if (value != _indicator) {
      _indicator = value;
      markNeedsPaint();
    }
  }

  GlassDecoration get decoration => _decoration;
  GlassDecoration _decoration;
  set decoration(GlassDecoration value) {
    if (value != _decoration) {
      _decoration = value;
      markNeedsPaint();
    }
  }

  LensOptics get optics => _optics;
  LensOptics _optics;
  set optics(LensOptics value) {
    if (value != _optics) {
      _optics = value;
      markNeedsPaint();
    }
  }

  GlassAppearance? get appearance => _appearance;
  GlassAppearance? _appearance;
  set appearance(GlassAppearance? value) {
    if (value != _appearance) {
      _appearance = value;
      markNeedsPaint();
    }
  }

  double get opacity => _opacity;
  double _opacity;
  set opacity(double value) {
    if (value != _opacity) {
      _opacity = value;
      markNeedsPaint();
    }
  }

  BackdropKey? get backdropKey => _backdropKey;
  BackdropKey? _backdropKey;
  set backdropKey(BackdropKey? value) {
    if (value != _backdropKey) {
      _backdropKey = value;
      markNeedsPaint();
    }
  }

  int get stages => _stages;
  int _stages;
  set stages(int value) {
    if (value != _stages) {
      _stages = value;
      markNeedsPaint();
    }
  }

  Brightness get brightness => _brightness;
  Brightness _brightness;
  set brightness(Brightness value) {
    if (value != _brightness) {
      _brightness = value;
      _own?.system = value;
      markNeedsPaint();
    }
  }

  TextDirection get textDirection => _textDirection;
  TextDirection _textDirection;
  set textDirection(TextDirection value) {
    if (value != _textDirection) {
      _textDirection = value;
      markNeedsPaint();
    }
  }

  double get devicePixelRatio => _devicePixelRatio;
  double _devicePixelRatio;
  set devicePixelRatio(double value) {
    if (value != _devicePixelRatio) {
      _devicePixelRatio = value;
      markNeedsPaint();
    }
  }

  // The appearance when none is given: the ambient brightness's, which does
  // not read the backdrop.
  GlassAppearance? _own;
  GlassAppearance get _colors =>
      _appearance ?? (_own ??= GlassAppearance(system: _brightness));

  /// The lens as drawn: [rect] scaled by the flex about its center and
  /// shifted by the drift, in the child's coordinates.
  Rect get drawnRect {
    final Rect r = _rect;
    return Rect.fromCenter(
      center: r.center + _drift,
      width: r.width * _flexScale.width,
      height: r.height * _flexScale.height,
    );
  }

  _LensUniforms? _uniforms;
  final BackdropKey _ownCapture = BackdropKey();
  final LayerHandle<ClipRectLayer> _clip = LayerHandle<ClipRectLayer>();
  final LayerHandle<BackdropFilterLayer> _pass =
      LayerHandle<BackdropFilterLayer>();

  void _clear() {
    _clip.layer = null;
    _pass.layer = null;
  }

  @override
  bool get alwaysNeedsCompositing => true;

  @override
  void dispose() {
    _clear();
    _uniforms?.shader.dispose();
    super.dispose();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    // The child first: the lens reads it.
    super.paint(context, offset);
    final Rect lens = drawnRect;
    if (_opacity <= 0 || lens.isEmpty) {
      _clear();
      return;
    }
    final ui.FragmentProgram? program = LiquidLens._program.program;
    if (program == null) {
      LiquidLens._program.load().then((_) {
        if (attached) {
          markNeedsPaint();
        }
      });
    }
    final RRect shape = RRect.fromRectAndRadius(
      lens.shift(offset),
      Radius.circular(lens.shortestSide / 2),
    );
    final double resting = (1 - _lift).clamp(0.0, 1.0);
    final double lifted = (4 * _lift).clamp(0.0, 1.0);
    if (program == null || !ui.ImageFilter.isShaderFilterSupported) {
      _clear();
      _paintPlain(context.canvas, shape, resting, lifted);
      return;
    }
    final _LensUniforms u = _uniforms ??= _LensUniforms(
      program.fragmentShader(),
    );

    // The lens's geometry in the capture's pixels: physical pixels of the
    // pass the backdrop is captured from.
    final Matrix4 toRoot = getTransformTo(null);
    final double pointSize =
        _devicePixelRatio *
        (MatrixUtils.transformPoint(toRoot, const Offset(1, 0)) -
                MatrixUtils.transformPoint(toRoot, Offset.zero))
            .distance;
    final Rect global = MatrixUtils.transformRect(toRoot, lens);
    final Rect lensPixels = Rect.fromLTRB(
      global.left * _devicePixelRatio,
      global.top * _devicePixelRatio,
      global.right * _devicePixelRatio,
      global.bottom * _devicePixelRatio,
    );
    // The lens's optics are in its own points: scaled by its flex.
    final double lensScale = math.sqrt(_flexScale.width * _flexScale.height);
    final GlassAppearance colors = _colors;
    final (double, double, double) rim = colors.lensRim;
    final (double, double, double) pill = colors.pill;
    final bool dark = colors.isDark;
    u
      ..pass.set(1, 0, pointSize, _ovalization)
      ..lens.set(
        lensPixels.center.dx,
        lensPixels.center.dy,
        lensPixels.width / 2,
        lensPixels.height / 2,
      )
      ..optics.set(_lift, lensScale, 1, _stages.toDouble())
      ..lensRim.set(rim.$1, rim.$2, rim.$3, 0)
      ..pill.set(pill.$1, pill.$2, pill.$3, 0)
      ..show.set(_opacity.clamp(0.0, 1.0), 0, 0, 0)
      ..inner.set(
        _optics.inner,
        _optics.innerHeight,
        _optics.blur,
        _optics.shadow,
      )
      ..face.set(_optics.faceBlack, _optics.rim, 0, 0)
      ..setTints(
        decorationTint(
          _indicator,
          lensPixels,
          textDirection: _textDirection,
          dark: dark,
        ),
        decorationTint(
          _decoration,
          lensPixels,
          textDirection: _textDirection,
          dark: dark,
        ),
      );

    // The decorations' drop shadows go under the lens, into what it reads
    // (around its shape only).
    paintGlassShadows(context.canvas, shape, _indicator.shadows, resting);
    paintGlassShadows(context.canvas, shape, _decoration.shadows, lifted);

    // The lens, over its child and whatever lies behind, with UIKit's
    // shadow around it.
    _clip.layer = context.pushClipRect(
      needsCompositing,
      offset,
      lens.inflate(_shadowMargin),
      (PaintingContext context, Offset offset) {
        final BackdropFilterLayer layer =
            (_pass.layer ??= BackdropFilterLayer())
              ..filter = ui.ImageFilter.shader(u.shader)
              ..backdropKey = _backdropKey ?? _ownCapture;
        context.pushLayer(layer, _paintNothing, offset);
      },
      oldLayer: _clip.layer,
    );

    paintGlassInnerShadows(
      context.canvas,
      shape,
      _indicator.innerShadows,
      resting,
    );
    paintGlassInnerShadows(
      context.canvas,
      shape,
      _decoration.innerShadows,
      lifted,
    );
  }

  // Without shader filters: a plain pill, frosted at rest and clearer with
  // a rim once lifted.
  void _paintPlain(Canvas canvas, RRect shape, double resting, double lifted) {
    final bool dark = _colors.isDark;
    final Color rest = dark ? const Color(0x59FFFFFF) : const Color(0xB3FFFFFF);
    final Color clear = dark
        ? const Color(0x26FFFFFF)
        : const Color(0x40FFFFFF);
    final double alpha = _opacity.clamp(0.0, 1.0);
    canvas.drawRRect(
      shape,
      Paint()
        ..color = Color.lerp(
          rest,
          clear,
          1 - resting,
        )!.withValues(alpha: Color.lerp(rest, clear, 1 - resting)!.a * alpha),
    );
    if (lifted > 0) {
      canvas.drawRRect(
        shape.deflate(0.5),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Color.fromRGBO(255, 255, 255, 0.6 * lifted * alpha),
      );
    }
  }

  static void _paintNothing(PaintingContext context, Offset offset) {}
}

/// Named bindings into the lens shader.
class _LensUniforms {
  _LensUniforms(this.shader)
    : pass = shader.getUniformVec4('uPass'),
      lens = shader.getUniformVec4('uLens'),
      optics = shader.getUniformVec4('uOptics'),
      lensRim = shader.getUniformVec4('uLensRim'),
      pill = shader.getUniformVec4('uPill'),
      show = shader.getUniformVec4('uShow'),
      inner = shader.getUniformVec4('uInner'),
      face = shader.getUniformVec4('uFace'),
      tints = shader.getUniformVec4Array('uTints');

  final ui.FragmentShader shader;
  final ui.UniformVec4Slot pass;
  final ui.UniformVec4Slot lens;
  final ui.UniformVec4Slot optics;
  final ui.UniformVec4Slot lensRim;
  final ui.UniformVec4Slot pill;
  final ui.UniformVec4Slot show;
  final ui.UniformVec4Slot inner;
  final ui.UniformVec4Slot face;
  final ui.UniformArray<ui.UniformVec4Slot> tints;

  /// The resting pill's and the lifted lens's tints, each at its gradient's
  /// start and end, along its axis (capture pixels): five slots each, as
  /// the tab bar's shader takes them.
  void setTints(GlassDecorationTint rest, GlassDecorationTint lens) {
    var i = 0;
    for (final GlassDecorationTint t in <GlassDecorationTint>[rest, lens]) {
      final (start, end, from, to, paint) = t;
      tints[i++].set(
        start.bright[0],
        start.bright[1],
        start.bright[2],
        start.alpha,
      );
      // .w: painted rather than tinted.
      tints[i++].set(
        start.dark[0],
        start.dark[1],
        start.dark[2],
        paint ? 1 : 0,
      );
      tints[i++].set(end.bright[0], end.bright[1], end.bright[2], end.alpha);
      tints[i++].set(end.dark[0], end.dark[1], end.dark[2], 0);
      tints[i++].set(from.dx, from.dy, to.dx, to.dy);
    }
  }
}
