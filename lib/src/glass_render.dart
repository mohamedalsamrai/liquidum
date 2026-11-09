part of 'glass.dart';

/// UIKit's inputs for glass of a style, by the short sides (points) of its
/// smallest and its largest shape, as its glass filter sets them (iOS 26.5).
/// A lone glass's are its own; a group's glass has one set for all its
/// shapes: the refraction and frost depth of its smallest, the blur of its
/// largest.
class _GlassOptics {
  _GlassOptics(double small, double large, GlassStyle style)
    : clear = style == GlassStyle.clear,
      inner = style == GlassStyle.clear
          ? math.min(small, 60)
          : math.min(0.8 * small, 60),
      innerHeight = style == GlassStyle.clear
          ? math.min(0.36 * small, 20)
          : math.min(0.25 * small, 20),
      frostDepth = math.max(small / 2, 1.5),
      heavySigma = style == GlassStyle.clear
          ? _clearHeavySigma
          : _heavySigma62 * _byHeight(large, _heavyScale),
      lightSigma = style == GlassStyle.clear
          ? _clearLightSigma
          : large <= 62
          ? _lightSigma62
          : math.sqrt(
              math.pow(_byHeight(large, _lightFit), 2) -
                  _lightFit62 * _lightFit62 +
                  _lightSigma62 * _lightSigma62,
            ),
      frostRamp = style == GlassStyle.clear
          ? _clearRamp
          : _ramp62 * _byHeight(small, _rampScale);

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

/// One shape of glass to draw: its box in the painting render object's
/// coordinates and its corner radius (points), its short side (points, in
/// its own coordinates), how materialized it is, whether it melts with the
/// others, and its tint.
class _GlassShape {
  const _GlassShape({
    required this.rect,
    required this.radius,
    required this.height,
    required this.amount,
    required this.joins,
    required this.tint,
  });

  final Rect rect;
  final double radius;
  final double height;
  final double amount;
  final bool joins;
  final Color? tint;
}

/// The layers and shaders that draw one glass of up to eight shapes (a lone
/// glass, or a group's of one style): its frost into the backdrop, then the
/// glass over it.
class _GlassPasses {
  static const int maxShapes = 8;

  // One shader per pass: a shader image filter reads its uniforms only when
  // it is composited.
  _GlassUniforms? _glassPass;
  _GlassUniforms? _frostPass;

  final LayerHandle<ClipRectLayer> _frostClip = LayerHandle<ClipRectLayer>();
  final LayerHandle<ClipPathLayer> _plainClip = LayerHandle<ClipPathLayer>();
  final LayerHandle<BackdropFilterLayer> _frostHeavy =
      LayerHandle<BackdropFilterLayer>();
  final LayerHandle<BackdropFilterLayer> _frostLight =
      LayerHandle<BackdropFilterLayer>();
  final LayerHandle<ClipRectLayer> _glassClip = LayerHandle<ClipRectLayer>();
  final LayerHandle<BackdropFilterLayer> _glassLayer =
      LayerHandle<BackdropFilterLayer>();
  final BackdropKey _frostCapture = BackdropKey();

  void clear() {
    _frostClip.layer = null;
    _plainClip.layer = null;
    _frostHeavy.layer = null;
    _frostLight.layer = null;
    _glassClip.layer = null;
    _glassLayer.layer = null;
  }

  void dispose() {
    clear();
    _glassPass?.shader.dispose();
    _frostPass?.shader.dispose();
  }

  /// Paints [shapes] (in [owner]'s coordinates, at most [maxShapes]) as one
  /// glass of [style], [owner] being painted at [offset].
  void paint(
    PaintingContext context,
    Offset offset,
    RenderBox owner,
    List<_GlassShape> shapes, {
    required GlassStyle style,
    required GlassAppearance appearance,
    required double spacing,
    required double devicePixelRatio,
  }) {
    final ui.FragmentProgram? program = Glass._program.program;
    if (shapes.isEmpty || program == null) {
      clear();
      return;
    }
    Rect bounds = shapes.first.rect;
    for (final _GlassShape shape in shapes.skip(1)) {
      bounds = bounds.expandToInclude(shape.rect);
    }
    bounds = bounds.shift(offset);
    if (!ui.ImageFilter.isShaderFilterSupported) {
      _paintPlain(context, offset, shapes, bounds, appearance);
      return;
    }
    _plainClip.layer = null;
    final _GlassUniforms glassPass = _glassPass ??= _GlassUniforms(
      program.fragmentShader(),
    );
    final _GlassUniforms frostPass = _frostPass ??= _GlassUniforms(
      program.fragmentShader(),
    );

    // The capture's pixels: physical pixels of the pass the backdrop is
    // captured from.
    final Matrix4 toRoot = owner.getTransformTo(null);
    final double k =
        devicePixelRatio *
        (MatrixUtils.transformPoint(toRoot, const Offset(1, 0)) -
                MatrixUtils.transformPoint(toRoot, Offset.zero))
            .distance;
    double small = double.infinity;
    double large = 0;
    double amount = 0;
    for (final _GlassShape shape in shapes) {
      small = math.min(small, shape.height);
      large = math.max(large, shape.height);
      amount = math.max(amount, shape.amount);
    }
    final optics = _GlassOptics(small, large, style);
    final bool isClear = optics.clear;
    final (double, double, double, double) face = isClear
        ? _GlassOptics.clearFace
        : appearance.face;
    final (double, double, double) rim = appearance.platterRim;

    void set(_GlassUniforms u, double pass) {
      u
        // UIKit's glass filter refracts along its shape's distance gradient
        // (no ovalization, unlike the lens's warp).
        ..pass.set(pass, k, shapes.length.toDouble(), 0)
        ..optics.set(
          optics.inner,
          optics.innerHeight,
          spacing * k,
          appearance.refraction,
        )
        ..frost.set(optics.frostDepth, optics.lightSigma, optics.frostRamp, 0)
        ..face.set(face.$1, face.$2, face.$3, face.$4)
        ..rim.set(rim.$1, rim.$2, rim.$3, isClear ? 0 : appearance.shadow)
        ..shadow.set(
          _GlassOptics.shadowOffset,
          _GlassOptics.shadowSigma,
          _GlassOptics.shadowCenter,
          _GlassOptics.shadowReach,
        )
        ..more.set(
          isClear ? _GlassOptics.clearChroma : appearance.chroma,
          0,
          _GlassOptics.rimCurvature,
          0,
        )
        ..glow.set(0, 0, 0, 0)
        ..setBleed(
          appearance.isDark ? _GlassOptics.bleedDark : _GlassOptics.bleedLight,
          isClear
              ? 0
              : _GlassOptics.bleedOpacity(large, dark: appearance.isDark),
        );
      for (var i = 0; i < maxShapes; i++) {
        if (i >= shapes.length) {
          u.shapes[i].set(0, 0, 0, 0);
          u.info[i].set(0, 0, 0, 0);
          continue;
        }
        final _GlassShape shape = shapes[i];
        final Rect global = MatrixUtils.transformRect(toRoot, shape.rect);
        u.shapes[i].set(
          global.center.dx * devicePixelRatio,
          global.center.dy * devicePixelRatio,
          global.width / 2 * devicePixelRatio,
          global.height / 2 * devicePixelRatio,
        );
        u.info[i].set(
          shape.radius * k,
          shape.amount,
          shape.joins ? 1 : 0,
          shape.tint == null ? 0 : 1,
        );
        u.setTint(i, GlassTint(shape.tint, darkAppearance: appearance.isDark));
      }
    }

    set(frostPass, 1);
    set(glassPass, 0);

    // The frost, into the backdrop: a heavy blur over the glass's bounds,
    // and the shader's light one over it, putting the backdrop back outside
    // the glass's frost, both from the backdrop as it was.
    final double sigma = optics.heavySigma * amount * k / devicePixelRatio;
    final BackdropFilterLayer heavy =
        (_frostHeavy.layer ??= BackdropFilterLayer())
          ..filter = ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma)
          ..backdropKey = _frostCapture;
    final BackdropFilterLayer light =
        (_frostLight.layer ??= BackdropFilterLayer())
          ..filter = ui.ImageFilter.shader(frostPass.shader)
          ..backdropKey = _frostCapture;
    _frostClip.layer = context.pushClipRect(true, Offset.zero, bounds, (
      PaintingContext context,
      Offset _,
    ) {
      context
        ..pushLayer(heavy, _paintNothing, Offset.zero)
        ..pushLayer(light, _paintNothing, Offset.zero);
    }, oldLayer: _frostClip.layer);

    // The glass, over its frost, and its shadow around it.
    _glassClip.layer = context.pushClipRect(
      true,
      Offset.zero,
      bounds.inflate(isClear ? 2 : _GlassOptics.shadowReach + 2),
      (PaintingContext context, Offset _) {
        final BackdropFilterLayer layer =
            (_glassLayer.layer ??= BackdropFilterLayer())
              ..filter = ui.ImageFilter.shader(glassPass.shader);
        context.pushLayer(layer, _paintNothing, Offset.zero);
      },
      oldLayer: _glassClip.layer,
    );
  }

  // Without shader filters: a plain frost in each shape.
  void _paintPlain(
    PaintingContext context,
    Offset offset,
    List<_GlassShape> shapes,
    Rect bounds,
    GlassAppearance appearance,
  ) {
    _frostClip.layer = null;
    _frostLight.layer = null;
    _glassClip.layer = null;
    _glassLayer.layer = null;
    final Path path = Path();
    for (final _GlassShape shape in shapes) {
      path.addRRect(
        RRect.fromRectAndRadius(
          shape.rect.shift(offset),
          Radius.circular(shape.radius),
        ),
      );
    }
    _plainClip.layer = context.pushClipPath(true, Offset.zero, bounds, path, (
      PaintingContext context,
      Offset _,
    ) {
      final BackdropFilterLayer layer =
          (_frostHeavy.layer ??= BackdropFilterLayer())
            ..filter = ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8);
      context.pushLayer(layer, (PaintingContext context, Offset _) {
        context.canvas.drawPath(
          path,
          Paint()
            ..color = appearance.isDark
                ? const Color(0x99202024)
                : const Color(0x99F2F2F7),
        );
      }, Offset.zero);
    }, oldLayer: _plainClip.layer);
  }

  static void _paintNothing(PaintingContext context, Offset offset) {}
}

/// A [Glass]: alone, it draws its own glass; in a [GlassGroup], the group
/// draws it, and it paints only its child.
class _RenderGlass extends RenderProxyBox {
  _RenderGlass({
    required this._style,
    required this._radius,
    required this._tint,
    required this._visible,
    required this._presence,
    required this.appearance,
    required this._hub,
    required this._repaint,
    required this._devicePixelRatio,
  });

  final GlassAppearance appearance;
  final _GlassPasses _passes = _GlassPasses();

  GlassStyle get style => _style;
  GlassStyle _style;
  set style(GlassStyle value) {
    if (value != _style) {
      _style = value;
      _changed();
    }
  }

  double? get radius => _radius;
  double? _radius;
  set radius(double? value) {
    if (value != _radius) {
      _radius = value;
      _changed();
    }
  }

  Color? get tint => _tint;
  Color? _tint;
  set tint(Color? value) {
    if (value != _tint) {
      _tint = value;
      _changed();
    }
  }

  /// Whether the glass is meant to show: while it dematerializes, it stands
  /// apart from its group.
  bool get visible => _visible;
  bool _visible;
  set visible(bool value) {
    if (value != _visible) {
      _visible = value;
      _changed();
    }
  }

  Animation<double> get presence => _presence;
  Animation<double> _presence;
  set presence(Animation<double> value) {
    if (value == _presence) {
      return;
    }
    if (attached) {
      _presence.removeListener(_changed);
      value.addListener(_changed);
    }
    _presence = value;
    _changed();
  }

  /// How materialized the glass is: UIKit's ease in and out of its
  /// presence.
  double get amount => Curves.easeInOut.transform(_presence.value);

  _GlassHub? get hub => _hub;
  _GlassHub? _hub;
  set hub(_GlassHub? value) {
    if (value == _hub) {
      return;
    }
    if (attached) {
      _hub?.remove(this);
      value?.add(this);
    }
    _hub = value;
    _passes.clear();
    markNeedsCompositingBitsUpdate();
    markNeedsPaint();
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

  void _changed() {
    markNeedsPaint();
    _hub?.changed();
  }

  /// The glass's corner radius (points).
  double get cornerRadius {
    final double capsule = size.shortestSide / 2;
    return math.min(_radius ?? capsule, capsule);
  }

  @override
  bool get alwaysNeedsCompositing => _hub == null;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _repaint.addListener(markNeedsPaint);
    _presence.addListener(_changed);
    _hub?.add(this);
  }

  @override
  void detach() {
    _repaint.removeListener(markNeedsPaint);
    _presence.removeListener(_changed);
    _hub?.remove(this);
    super.detach();
  }

  @override
  void dispose() {
    _passes.dispose();
    super.dispose();
  }

  @override
  void performLayout() {
    super.performLayout();
    if (_hub == null) {
      appearance.height = size.shortestSide;
    } else {
      _hub!.changed();
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final _GlassHub? hub = _hub;
    if (hub == null) {
      final double amount = this.amount;
      _passes.paint(
        context,
        offset,
        this,
        <_GlassShape>[
          if (!size.isEmpty && amount > 0)
            _GlassShape(
              rect: Offset.zero & size,
              radius: cornerRadius,
              height: size.shortestSide,
              amount: amount,
              joins: true,
              tint: _tint,
            ),
        ],
        style: _style,
        appearance: appearance,
        spacing: 0,
        devicePixelRatio: _devicePixelRatio,
      );
    } else {
      _passes.clear();
      // A move the group did not paint (one within a repaint boundary of
      // its own): the group paints it next frame.
      final _RenderGlassGroup? group = hub.group;
      if (group != null && group.attached) {
        final Rect? painted = group._painted[this];
        final Rect now = MatrixUtils.transformRect(
          getTransformTo(group),
          Offset.zero & size,
        );
        if (painted != now) {
          SchedulerBinding.instance
            ..addPostFrameCallback((_) => hub.changed())
            ..ensureVisualUpdate();
        }
      }
    }
    super.paint(context, offset);
  }
}

/// A [GlassGroup]: draws its glass, a glass per style of up to eight shapes,
/// before its child.
class _RenderGlassGroup extends RenderProxyBox {
  _RenderGlassGroup({
    required this.hub,
    required this._spacing,
    required this.appearance,
    required this.clearAppearance,
    required this._repaint,
    required this._devicePixelRatio,
  });

  final _GlassHub hub;
  final GlassAppearance appearance;

  /// The appearance of the group's clear glass: the system's (UIKit draws
  /// it as a glass group of its own, which does not follow the backdrop).
  final GlassAppearance clearAppearance;
  final List<_GlassPasses> _passes = <_GlassPasses>[];

  /// The box of each glass where the group last painted it.
  final Map<_RenderGlass, Rect> _painted = <_RenderGlass, Rect>{};

  double get spacing => _spacing;
  double _spacing;
  set spacing(double value) {
    if (value != _spacing) {
      _spacing = value;
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

  @override
  bool get alwaysNeedsCompositing => true;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    hub.group = this;
    _repaint.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    if (hub.group == this) {
      hub.group = null;
    }
    _repaint.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void dispose() {
    for (final _GlassPasses passes in _passes) {
      passes.dispose();
    }
    super.dispose();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    _painted.clear();
    final regular = <_GlassShape>[];
    final clear = <_GlassShape>[];
    for (final _RenderGlass glass in hub.members) {
      if (!glass.attached || !glass.hasSize || glass.size.isEmpty) {
        continue;
      }
      final Rect rect = MatrixUtils.transformRect(
        glass.getTransformTo(this),
        Offset.zero & glass.size,
      );
      _painted[glass] = rect;
      final double amount = glass.amount;
      if (amount <= 0) {
        continue;
      }
      (glass.style == GlassStyle.clear ? clear : regular).add(
        _GlassShape(
          rect: rect,
          radius: glass.cornerRadius * rect.height / glass.size.height,
          height: glass.size.shortestSide,
          amount: amount,
          joins: glass.visible,
          tint: glass.tint,
        ),
      );
    }
    // The group's appearance follows its largest regular glass.
    if (regular.isNotEmpty) {
      appearance.height = regular
          .map((_GlassShape s) => s.height)
          .reduce(math.max);
    }
    var used = 0;
    void draw(List<_GlassShape> shapes, GlassStyle style) {
      for (var i = 0; i < shapes.length; i += _GlassPasses.maxShapes) {
        if (used == _passes.length) {
          _passes.add(_GlassPasses());
        }
        _passes[used++].paint(
          context,
          offset,
          this,
          shapes.sublist(
            i,
            math.min(i + _GlassPasses.maxShapes, shapes.length),
          ),
          style: style,
          appearance: style == GlassStyle.clear ? clearAppearance : appearance,
          spacing: _spacing,
          devicePixelRatio: _devicePixelRatio,
        );
      }
    }

    draw(regular, GlassStyle.regular);
    draw(clear, GlassStyle.clear);
    for (var i = used; i < _passes.length; i++) {
      _passes[i].clear();
    }
    super.paint(context, offset);
  }
}

/// Named bindings into the glass shader.
class _GlassUniforms {
  _GlassUniforms(this.shader)
    : pass = shader.getUniformVec4('uPass'),
      optics = shader.getUniformVec4('uOptics'),
      face = shader.getUniformVec4('uFace'),
      rim = shader.getUniformVec4('uRim'),
      shadow = shader.getUniformVec4('uShadow'),
      more = shader.getUniformVec4('uMore'),
      frost = shader.getUniformVec4('uFrost'),
      glow = shader.getUniformVec4('uGlow'),
      shapes = shader.getUniformVec4Array('uShapes'),
      info = shader.getUniformVec4Array('uShapeInfo'),
      tints = shader.getUniformVec4Array('uShapeTints'),
      bleed = shader.getUniformVec4Array('uBleed');

  final ui.FragmentShader shader;
  final ui.UniformVec4Slot pass;
  final ui.UniformVec4Slot optics;
  final ui.UniformVec4Slot face;
  final ui.UniformVec4Slot rim;
  final ui.UniformVec4Slot shadow;
  final ui.UniformVec4Slot more;
  final ui.UniformVec4Slot frost;
  final ui.UniformVec4Slot glow;
  final ui.UniformArray<ui.UniformVec4Slot> shapes;
  final ui.UniformArray<ui.UniformVec4Slot> info;
  final ui.UniformArray<ui.UniformVec4Slot> tints;
  final ui.UniformArray<ui.UniformVec4Slot> bleed;

  void setBleed(List<List<double>> matrix, double opacity) {
    for (var i = 0; i < 3; i++) {
      bleed[i].set(matrix[i][0], matrix[i][1], matrix[i][2], matrix[i][3]);
    }
    bleed[3].set(opacity, 0, 0, 0);
  }

  /// Shape [i]'s tint: one color (no gradient).
  void setTint(int i, GlassTint t) {
    tints[2 * i].set(t.bright[0], t.bright[1], t.bright[2], t.alpha);
    tints[2 * i + 1].set(t.dark[0], t.dark[1], t.dark[2], 0);
  }
}
