part of 'glass.dart';

/// The sizes of UIKit's glass buttons (`UIButton.Configuration.buttonSize`).
enum GlassButtonSize {
  /// 32pt tall, 15pt text (as [small] on iOS 26).
  mini,

  /// 32pt tall, 15pt text.
  small,

  /// 38.33pt tall, 17pt text: UIKit's default.
  medium,

  /// 54.33pt tall, 17pt text.
  large,
}

/// UIKit's glass button (`UIButton.Configuration.glass()` and its kin): a
/// capsule of interactive [Glass] with a [label], an [icon] or both on it.
///
/// ```dart
/// GlassButton(label: 'Done', onPressed: save)
/// GlassButton(icon: CupertinoIcons.add, onPressed: add)
/// GlassButton(label: 'Buy', prominent: true, onPressed: buy)
/// ```
///
/// The four styles are UIKit's: [prominent] fills the glass with [tint]
/// (the system blue by default) under a white label (`prominentGlass()`);
/// [style] makes the glass clear (`clearGlass()`; `prominentClearGlass()`
/// grays clear glass a little, whatever the tint, as UIKit's).
///
/// The label is vibrant, as UIKit's: drawn from the glass under it, deeper
/// and darker, so it takes the colors behind the button.
///
/// Pressed, the glass swells, lightens and glows under the finger and
/// springs back when let go, as UIKit's (see [Glass.interactive]). With no
/// [onPressed] the button is disabled: still glass, with a faint label.
///
/// Sizes and spacing as UIKit's on iOS 26.5: a medium button is 38.33pt
/// tall with 12pt either side of its 17pt label, or a 34.33pt circle with
/// only an icon.
class GlassButton extends StatelessWidget {
  const GlassButton({
    super.key,
    required this.onPressed,
    this.label,
    this.icon,
    this.prominent = false,
    this.style = GlassStyle.regular,
    this.tint,
    this.size = GlassButtonSize.medium,
  }) : assert(label != null || icon != null, 'A label, an icon or both.');

  /// Called when the button is tapped; null disables it.
  final VoidCallback? onPressed;

  final String? label;

  /// Shown before the label (as UIKit's image), or alone in a circle.
  final IconData? icon;

  /// UIKit's prominent glass: filled with [tint], with a white label.
  final bool prominent;

  final GlassStyle style;

  /// The fill of a [prominent] button: the system blue by default. UIKit's
  /// plain and clear glass buttons ignore it.
  final Color? tint;

  final GlassButtonSize size;

  bool get _enabled => onPressed != null;

  static const double _iconGap = 6;

  // UIKit's metrics per size (iOS 26.5): the capsule's height with a label,
  // the circle's with only an icon, the padding either side, the text size
  // and tracking, the icon's size and the width UIKit gives it (its
  // symbol's box, whatever the glyph).
  ({
    double height,
    double circle,
    double side,
    double font,
    double tracking,
    double icon,
    double iconBox,
  })
  get _metrics => switch (size) {
    GlassButtonSize.mini || GlassButtonSize.small => (
      height: 32,
      circle: 28,
      side: 10,
      font: 15,
      tracking: -0.23,
      icon: 19,
      iconBox: 20.33,
    ),
    GlassButtonSize.medium => (
      height: 38.33,
      circle: 34.33,
      side: 12,
      font: 17,
      tracking: -0.43,
      icon: 22,
      iconBox: 23,
    ),
    GlassButtonSize.large => (
      height: 54.33,
      circle: 50.33,
      side: 20,
      font: 17,
      tracking: -0.43,
      icon: 22,
      iconBox: 23,
    ),
  };

  // The glass's fill: prominent glass's tint.
  Color? get _fill => prominent && _enabled && style == GlassStyle.regular
      ? (tint ?? GlassTabBarStyle.systemBlue)
      : null;

  // UIKit's gray materials (iOS 26.5): over prominent clear glass, a gray of
  // 0.22 of its luma plus 0.25, at 0.16; over disabled prominent glass, its
  // color with its luma pulled to about half (less 0.93 of it, plus 0.5), at
  // 0.45.
  _GlassMaterial? get _material {
    if (!prominent) {
      return null;
    }
    if (!_enabled) {
      return (gain: 1, lumaWeight: -0.926, offset: 0.498, opacity: 0.45);
    }
    if (style == GlassStyle.clear) {
      return (gain: 0, lumaWeight: 0.224, offset: 0.25, opacity: 0.16);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final m = _metrics;
    final bool round = label == null;
    final bool white = _fill != null;
    final Widget content = Builder(
      builder: (BuildContext context) {
        final bool dark =
            _glassIsDarkOf(context) ??
            MediaQuery.platformBrightnessOf(context) == Brightness.dark;
        return _GlassLabel(
          label: label,
          icon: icon,
          style: TextStyle(
            fontSize: m.font,
            fontWeight: FontWeight.w400,
            letterSpacing: m.tracking,
            decoration: TextDecoration.none,
          ),
          iconSize: m.icon,
          iconBox: m.iconBox,
          gap: _iconGap,
          side: round ? 0 : m.side,
          // UIKit's label colors: the label color (black on light glass,
          // white on dark), white on prominent glass, and the tertiary
          // label color (at its 0.3 alpha) when disabled.
          color: !_enabled
              ? (dark ? const Color(0xFFEBEBF5) : const Color(0xFF3C3C43))
              : white || dark
              ? const Color(0xFFFFFFFF)
              : const Color(0xFF000000),
          strength: _enabled ? 1 : 0.3,
          textScaler: MediaQuery.textScalerOf(context),
          devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
          press: _glassPressOf(context),
        );
      },
    );
    return Semantics(
      button: true,
      enabled: _enabled,
      label: label,
      child: GestureDetector(
        onTap: onPressed,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          height: round ? m.circle : m.height,
          width: round ? m.circle : null,
          child: Glass._button(
            _material,
            style: style,
            tint: _fill,
            interactive: _enabled,
            child: content,
          ),
        ),
      ),
    );
  }
}

/// A glass button's icon and label, side by side and centered, drawn
/// vibrantly: through the glass under them, with [color] (plainly in
/// [color] where shader filters are not supported).
class _GlassLabel extends LeafRenderObjectWidget {
  const _GlassLabel({
    required this.label,
    required this.icon,
    required this.style,
    required this.iconSize,
    required this.iconBox,
    required this.gap,
    required this.side,
    required this.color,
    required this.strength,
    required this.textScaler,
    required this.devicePixelRatio,
    required this.press,
  });

  final String? label;
  final IconData? icon;
  final TextStyle style;
  final double iconSize;
  final double iconBox;
  final double gap;
  final double side;
  final Color color;
  final double strength;
  final TextScaler textScaler;
  final double devicePixelRatio;

  /// The glass's press: UIKit's label shows half as strongly while pressed
  /// (under the press's glow, which it does not take).
  final _GlassPressView? press;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderGlassLabel()..configure(this);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderGlassLabel).configure(this);
  }
}

class _RenderGlassLabel extends RenderBox {
  static final ShaderProgram _program = ShaderProgram('vibrant.frag');

  // UIKit's vibrant matrix for labels on light glass (gain, luma weight),
  // and how much of it shows (iOS 26.5).
  static const double _gain = 1.5;
  static const double _lumaWeight = 1.4;
  static const double _scale = 0.69;
  static const double _offset = 0.9;

  // The mask is drawn this much finer than the screen, for the swell.
  static const double _maskScale = 1.5;

  final TextPainter _text = TextPainter(
    textDirection: TextDirection.ltr,
    maxLines: 1,
    ellipsis: '…',
  );
  final TextPainter _icon = TextPainter(textDirection: TextDirection.ltr);
  _GlassLabel? _config;
  ui.Image? _mask;
  ui.FragmentShader? _shader;
  final LayerHandle<ClipRectLayer> _clip = LayerHandle<ClipRectLayer>();
  final LayerHandle<BackdropFilterLayer> _filter =
      LayerHandle<BackdropFilterLayer>();

  _GlassPressView? _press;

  void configure(_GlassLabel c) {
    final _GlassLabel? old = _config;
    _config = c;
    if (c.press != _press) {
      if (attached) {
        _press?.listenable.removeListener(markNeedsPaint);
        c.press?.listenable.addListener(markNeedsPaint);
      }
      _press = c.press;
      markNeedsPaint();
    }
    if (old == null ||
        old.label != c.label ||
        old.icon != c.icon ||
        old.style != c.style ||
        old.iconSize != c.iconSize ||
        old.iconBox != c.iconBox ||
        old.gap != c.gap ||
        old.side != c.side ||
        old.color != c.color ||
        old.textScaler != c.textScaler ||
        old.devicePixelRatio != c.devicePixelRatio) {
      final IconData? icon = c.icon;
      _text.text = c.label == null
          ? null
          : TextSpan(
              text: c.label,
              style: c.style.copyWith(color: c.color),
            );
      _text.textScaler = c.textScaler;
      _icon.text = icon == null
          ? null
          : TextSpan(
              text: String.fromCharCode(icon.codePoint),
              style: TextStyle(
                inherit: false,
                color: c.color,
                fontSize: c.iconSize,
                fontFamily: icon.fontFamily,
                package: icon.fontPackage,
                fontFamilyFallback: icon.fontFamilyFallback,
                height: 1,
              ),
            );
      _icon.textScaler = c.textScaler;
      markNeedsLayout();
    } else if (old.strength != c.strength) {
      markNeedsPaint();
    }
  }

  bool get _hasIcon => _icon.text != null;

  // The icon's box: UIKit's symbol box, or the glyph if wider.
  double get _iconWidth => math.max(_config!.iconBox, _icon.width);
  bool get _hasText => _text.text != null;

  double get _contentWidth {
    final _GlassLabel c = _config!;
    var w = 0.0;
    if (_hasIcon) {
      w += _iconWidth;
    }
    if (_hasIcon && _hasText) {
      w += c.gap;
    }
    if (_hasText) {
      w += _text.width;
    }
    return w;
  }

  void _layoutPainters(double maxWidth) {
    final _GlassLabel c = _config!;
    if (_hasIcon) {
      _icon.layout();
    }
    if (_hasText) {
      final double room =
          maxWidth - 2 * c.side - (_hasIcon ? _iconWidth + c.gap : 0);
      _text.layout(maxWidth: math.max(0, room));
    }
  }

  @override
  double computeMinIntrinsicWidth(double height) =>
      computeMaxIntrinsicWidth(height);

  @override
  double computeMaxIntrinsicWidth(double height) {
    _layoutPainters(double.infinity);
    return _contentWidth + 2 * _config!.side;
  }

  @override
  double computeMinIntrinsicHeight(double width) =>
      computeMaxIntrinsicHeight(width);

  @override
  double computeMaxIntrinsicHeight(double width) {
    _layoutPainters(width);
    return math.max(_hasText ? _text.height : 0, _hasIcon ? _icon.height : 0);
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    _layoutPainters(constraints.maxWidth);
    return _sizeFor(constraints);
  }

  Size _sizeFor(BoxConstraints constraints) {
    final double h = constraints.hasBoundedHeight
        ? constraints.maxHeight
        : math.max(_hasText ? _text.height : 0, _hasIcon ? _icon.height : 0);
    return constraints.constrain(Size(_contentWidth + 2 * _config!.side, h));
  }

  @override
  void performLayout() {
    _layoutPainters(constraints.maxWidth);
    size = _sizeFor(constraints);
    _mask?.dispose();
    _mask = null;
  }

  // Where the icon and label are painted: centered together.
  Offset get _iconAt => Offset(
    (size.width - _contentWidth) / 2 + (_iconWidth - _icon.width) / 2,
    (size.height - _icon.height) / 2,
  );

  Offset get _textAt => Offset(
    (size.width - _contentWidth) / 2 +
        (_hasIcon ? _iconWidth + _config!.gap : 0),
    (size.height - _text.height) / 2,
  );

  // The box the glyphs are in, a little grown.
  Rect get _bounds => Rect.fromLTWH(
    (size.width - _contentWidth) / 2,
    0,
    _contentWidth,
    size.height,
  ).inflate(2);

  void _paintGlyphs(Canvas canvas, Offset offset) {
    if (_hasIcon) {
      _icon.paint(canvas, offset + _iconAt);
    }
    if (_hasText) {
      _text.paint(canvas, offset + _textAt);
    }
  }

  ui.Image _buildMask() {
    final Rect bounds = _bounds;
    final double k = _config!.devicePixelRatio * _maskScale;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
      ..scale(k)
      ..translate(-bounds.left, -bounds.top);
    _paintGlyphs(canvas, Offset.zero);
    final ui.Picture picture = recorder.endRecording();
    final ui.Image image = picture.toImageSync(
      math.max(1, (bounds.width * k).ceil()),
      math.max(1, (bounds.height * k).ceil()),
    );
    picture.dispose();
    return image;
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _press?.listenable.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _press?.listenable.removeListener(markNeedsPaint);
    super.detach();
  }

  // The label's strength now: its own, halved while fully pressed (UIKit's
  // pressed glass button, iOS 26.5).
  double get _strength => _config!.strength * (1 - 0.5 * (_press?.amount ?? 0));

  @override
  bool get alwaysNeedsCompositing => true;

  @override
  void paint(PaintingContext context, Offset offset) {
    final _GlassLabel c = _config!;
    final ui.FragmentProgram? program = _program.program;
    if (program == null) {
      _program.load().then((_) {
        if (attached) {
          markNeedsPaint();
        }
      });
    }
    if (program == null || !ui.ImageFilter.isShaderFilterSupported) {
      _clip.layer = null;
      _filter.layer = null;
      if (_strength < 1) {
        context.pushOpacity(offset, (_strength * 255).round(), (
          PaintingContext context,
          Offset offset,
        ) {
          _paintGlyphs(context.canvas, offset);
        });
      } else {
        _paintGlyphs(context.canvas, offset);
      }
      return;
    }
    final ui.Image mask = _mask ??= _buildMask();
    final ui.FragmentShader shader = _shader ??= program.fragmentShader();
    final Rect bounds = _bounds.shift(offset);
    // The mask's box in capture pixels: the label's box on screen.
    final Matrix4 toRoot = getTransformTo(null);
    final Rect screen = MatrixUtils.transformRect(toRoot, _bounds);
    final double dpr = c.devicePixelRatio;
    shader
      ..setFloat(2, screen.left * dpr)
      ..setFloat(3, screen.top * dpr)
      ..setFloat(4, screen.width * dpr)
      ..setFloat(5, screen.height * dpr)
      ..setFloat(6, _gain)
      ..setFloat(7, _lumaWeight)
      ..setFloat(8, _scale)
      ..setFloat(9, _strength)
      ..setFloat(10, _offset * c.color.r)
      ..setFloat(11, _offset * c.color.g)
      ..setFloat(12, _offset * c.color.b)
      ..setFloat(13, 0)
      ..setImageSampler(1, mask);
    _clip.layer = context.pushClipRect(true, Offset.zero, bounds, (
      PaintingContext context,
      Offset _,
    ) {
      final BackdropFilterLayer layer =
          (_filter.layer ??= BackdropFilterLayer())
            ..filter = ui.ImageFilter.shader(shader);
      context.pushLayer(
        layer,
        (PaintingContext context, Offset offset) {},
        Offset.zero,
      );
    }, oldLayer: _clip.layer);
  }

  @override
  void dispose() {
    _clip.layer = null;
    _filter.layer = null;
    _mask?.dispose();
    _shader?.dispose();
    _text.dispose();
    _icon.dispose();
    super.dispose();
  }
}
