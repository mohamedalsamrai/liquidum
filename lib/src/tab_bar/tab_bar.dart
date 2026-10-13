import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../glass_backdrop.dart';
import '../shader_program.dart';
import 'appearance.dart';
import 'decoration.dart';
import 'item.dart';
import 'physics.dart';
import 'style.dart';
import 'tab_content.dart';
import 'tint.dart';

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

/// The optical stages of the glass, as bits of [GlassTabBar.debugOptics].
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

/// An iOS 26 tab bar: a glass platter holding the tabs, and a lens that
/// selects one. Press and slide to carry the lens between tabs; release to
/// select the tab under it.
///
/// The bar is 62pt high. As UIKit's, with four tabs or more it is as wide as
/// it is allowed to be, and with fewer it is only as wide as its tabs need
/// (274pt for three) when allowed to be narrower: center it. UIKit floats it
/// 21pt from the sides and bottom of the screen. It adapts to what is
/// behind it when that is wrapped in a [GlassBackdrop]. [GlassTabScaffold]
/// does all of this, and gives each tab its page.
///
/// In a right-to-left [Directionality], the first tab is on the right, as in
/// UIKit.
class GlassTabBar extends StatefulWidget {
  const GlassTabBar({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    this.onReselected,
    this.selectedColor,
    this.unselectedColor,
    this.badgeColor,
    this.brightness,
    this.adaptive = true,
    this.labelStyle,
    this.glassColor,
    this.indicatorColor,
    this.lensColor,
    this.glass,
    this.indicator,
    this.lens,
    this.padding,
    this.debugView = GlassTabBarDebugView.none,
    this.debugShareBackdrop = true,
    this.debugInspector,
    this.debugHold,
    this.debugHideContent = false,
    this.debugOptics = GlassTabBarOptics.all,
    this.debugLift,
  });

  /// Height of the bar, as on iOS 26.
  static const double height = 62;

  final List<GlassTabItem> items;

  /// The selected tab, by its index in [items].
  final int selectedIndex;

  /// Called with a tab's index when the finger lets go over another tab
  /// than the selected one. The bar shows it selected only once
  /// [selectedIndex] says so, and otherwise goes back.
  final ValueChanged<int> onSelected;

  /// Called with the selected tab's index when the finger lets go over it
  /// again, for example to scroll its page to the top.
  final ValueChanged<int>? onReselected;

  /// The selected tab's icon and label color, as `UITabBar.tintColor`.
  /// Defaults to the system blue.
  ///
  /// As UIKit does, the bar mixes it with the glass under the tab: it shows
  /// half of that glass plus this color, less half a unit in the light
  /// appearance. Over the resting selection that comes out close to the
  /// color itself. Dynamic colors (such as `CupertinoColors.systemPink`)
  /// resolve for the bar's own appearance.
  final Color? selectedColor;

  /// The other tabs' icon and label color. By default (null) they take
  /// UIKit's adaptive colors from the glass under them, which UIKit's iOS 26
  /// bar always uses (it ignores `unselectedItemTintColor`). When set, they
  /// are drawn in this color as it is.
  final Color? unselectedColor;

  /// Badges' color. Defaults to the system red.
  final Color? badgeColor;

  /// The appearance the bar starts from, as UIKit's
  /// `overrideUserInterfaceStyle`. Defaults to the platform's.
  final Brightness? brightness;

  /// Whether the bar turns dark over dark content and light over light
  /// content, as UIKit's does (it needs a [GlassBackdrop] under it). When
  /// false, it keeps [brightness].
  final bool adaptive;

  /// Merged into the labels' style (UIKit's: 10pt, semibold when selected
  /// and medium otherwise), for example to set a font family. Its color is
  /// ignored.
  final TextStyle? labelStyle;

  /// Tints the bar's glass, as `UIGlassEffect.tintColor` tints glass: the
  /// glass takes the color, deeper where it is darker (over dark content,
  /// or in the dark appearance) and as it is where it is white. The color's
  /// alpha sets how strongly: a translucent color lets the plain glass show
  /// through. None by default.
  final Color? glassColor;

  /// Tints the glass under the selected tab at rest, the same way. UIKit's
  /// is a gray tint of the glass (this is on top of it). None by default.
  final Color? indicatorColor;

  /// Tints the lens that the selection lifts into while the bar is pressed
  /// or dragged, the same way. UIKit's lens is clear. None by default.
  final Color? lensColor;

  /// The bar's glass decorated: a tint or a gradient, drop shadows (in place
  /// of UIKit's) and inner shadows. [glassColor] is short for its color.
  final GlassDecoration? glass;

  /// The selection at rest decorated the same way ([indicatorColor] is
  /// short for its color).
  final GlassDecoration? indicator;

  /// The lens, while the selection moves, decorated the same way
  /// ([lensColor] is short for its color).
  final GlassDecoration? lens;

  /// Space inside the bar around its tabs, as a box's padding: the bar grows
  /// with it, the tabs keep their 54pt height. Defaults to UIKit's 4pt all
  /// round (a 62pt bar). Directional padding follows the app's direction.
  ///
  /// The lens the selection lifts into still rises out of the bar as UIKit's
  /// does, 4pt past its top and bottom edges whatever the padding.
  final EdgeInsetsGeometry? padding;

  /// The bar's height with [padding] (UIKit's, 62pt, without).
  static double heightWith(EdgeInsetsGeometry? padding) =>
      GlassTabBarPhysics.tabHeight +
      (padding ?? const EdgeInsets.all(GlassTabBarPhysics.inset)).vertical;

  GlassTabBarStyle get _style => GlassTabBarStyle(
    selectedColor: selectedColor,
    unselectedColor: unselectedColor,
    badgeColor: badgeColor,
    labelStyle: labelStyle,
  );

  final GlassTabBarDebugView debugView;

  /// Whether the lens reads the same backdrop capture as the bar, taken
  /// before any of the bar's glass. Turn off only to see what the lens would
  /// read otherwise: the bar's rendered glass.
  final bool debugShareBackdrop;

  /// Where [GlassTabBarDebugView.sampling] draws its inspector, in the bar's
  /// coordinates. Defaults to a panel above the bar.
  final Rect? debugInspector;

  /// Holds a press at this point, in the bar's coordinates, from the first
  /// frame on: the lens stays lifted there without a real touch, for still
  /// comparisons.
  final Offset? debugHold;

  /// Draws no tab content, so the glass's optics can be looked at alone.
  final bool debugHideContent;

  /// The optical stages drawn (a [GlassTabBarOptics] mask), to compare them
  /// one at a time.
  final int debugOptics;

  /// Draws the glass's optics at this lift progress (0 to 1) instead of the
  /// lens's, to compare the transition between resting and lifted at fixed
  /// points.
  final double? debugLift;

  static final ShaderProgram _field = ShaderProgram('field.frag');
  static final ShaderProgram _backdrop = ShaderProgram('backdrop.frag');

  /// Loads the bar's shaders ahead of time, so the bar shows from the first
  /// frame. Optional: otherwise it loads them itself, and appears once they
  /// are in.
  static Future<void> precache() =>
      Future.wait(<Future<void>>[_field.load(), _backdrop.load()]);

  @override
  State<GlassTabBar> createState() => _GlassTabBarState();
}

class _GlassTabBarState extends State<GlassTabBar>
    with SingleTickerProviderStateMixin {
  late final GlassTabBarPhysics _physics = GlassTabBarPhysics(
    count: widget.items.length,
    selectedIndex: _slot(widget.selectedIndex),
  );

  // Tabs are laid out in slots from the left: in a right-to-left
  // Directionality, the first tab takes the last slot. A slot and an index
  // map to each other the same way.
  bool _rtl = false;
  int _slot(int index) => _rtl ? widget.items.length - 1 - index : index;

  // Whether the tabs were last built for the dark appearance: their colors
  // resolve for it, and the shader's selected tint goes with them.
  bool _contentDark = false;
  late final Ticker _ticker = createTicker(_tick);
  final _Frame _frame = _Frame();
  int? _pointer;

  // The adaptive appearance, fed by readings of the backdrop under the bar:
  // UIKit reads it about every frame; this, every 50ms while frames are
  // being drawn.
  final GlassAppearance _appearance = GlassAppearance();
  Timer? _sampler;
  bool _sampling = false;
  int _sampledFrame = -1;
  static int _frames = 0;
  static bool _counting = false;

  // The raw vsync time: on the same clock as pointer event time stamps, so
  // touches take effect at the moment they happened.
  static double get _frameTime =>
      SchedulerBinding.instance.currentSystemFrameTimeStamp.inMicroseconds /
      1e6;

  static double _timeOf(PointerEvent event) =>
      event.timeStamp.inMicroseconds / 1e6;

  void _tick(Duration _) {
    final double now = _frameTime;
    if (!(_physics.tick(now) | _appearance.tick(now))) {
      _ticker.stop();
    }
    if (_appearance.isDark != _contentDark) {
      setState(() => _contentDark = _appearance.isDark);
    }
    _frame.notify();
  }

  Future<void> _sample() async {
    if (_sampling || !mounted || _frames == _sampledFrame) {
      return;
    }
    final RenderObject? box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) {
      return;
    }
    final GlassBackdropState? backdrop = GlassBackdrop.under(
      MatrixUtils.transformRect(
        box.getTransformTo(null),
        Offset.zero & box.size,
      ),
    );
    if (backdrop == null) {
      return;
    }
    _sampling = true;
    _sampledFrame = _frames;
    try {
      final double? luma = await backdrop.meanLuma(
        GlassAppearance.sampleArea(
          MatrixUtils.transformRect(
            box.getTransformTo(null),
            Offset.zero & box.size,
          ),
        ),
      );
      if (mounted && luma != null) {
        _appearance.sample(luma);
        _wake();
      }
    } finally {
      _sampling = false;
    }
  }

  void _wake() {
    if (!_ticker.isActive) {
      _ticker.start();
    }
  }

  void _handlePointer(PointerEvent event) {
    switch (event) {
      case PointerDownEvent():
        if (_pointer != null) {
          return;
        }
        _pointer = event.pointer;
        _physics.pointerDown(event.localPosition, time: _timeOf(event));
      case PointerMoveEvent():
        if (event.pointer != _pointer) {
          return;
        }
        _physics.pointerMove(event.localPosition, time: _timeOf(event));
      case PointerUpEvent():
        if (event.pointer != _pointer) {
          return;
        }
        _pointer = null;
        final int index = _slot(_physics.pointerUp(time: _timeOf(event)));
        if (index == widget.selectedIndex) {
          widget.onReselected?.call(index);
        } else {
          widget.onSelected(index);
          // If the choice is not taken up, go back to the selected tab.
          SchedulerBinding.instance.addPostFrameCallback((_) {
            final int selected = _slot(widget.selectedIndex);
            if (mounted &&
                _pointer == null &&
                _physics.selectedIndex != selected) {
              _physics.select(selected);
              _wake();
            }
          });
        }
      case PointerCancelEvent():
        if (event.pointer != _pointer) {
          return;
        }
        _pointer = null;
        _physics.pointerCancel(time: _timeOf(event));
      default:
        return;
    }
    _wake();
  }

  @override
  void initState() {
    super.initState();
    if (!_counting) {
      _counting = true;
      SchedulerBinding.instance.addPersistentFrameCallback((_) => _frames++);
    }
    _sampler = Timer.periodic(
      const Duration(milliseconds: 50),
      (_) => _sample(),
    );
    GlassTabBar.precache().then((_) {
      if (mounted) {
        _frame.notify();
      }
    });
    final Offset? hold = widget.debugHold;
    if (hold != null) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _physics.pointerDown(hold);
          _wake();
        }
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bool rtl = Directionality.maybeOf(context) == TextDirection.rtl;
    if (rtl != _rtl) {
      _rtl = rtl;
      _physics.select(_slot(widget.selectedIndex));
    }
    _configureAppearance();
    _wake();
  }

  void _configureAppearance() {
    _appearance
      ..adaptive = widget.adaptive
      ..system = widget.brightness ?? MediaQuery.platformBrightnessOf(context);
  }

  @override
  void didUpdateWidget(GlassTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _configureAppearance();
    final int selected = _slot(widget.selectedIndex);
    if (selected != _physics.selectedIndex) {
      _physics.select(selected);
    }
    _wake();
  }

  @override
  void dispose() {
    _sampler?.cancel();
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  // The widest label, as UIKit sizes tabs by it: selected, which is widest.
  static double _widestLabel(
    BuildContext context,
    List<GlassTabItem> items,
    GlassTabBarStyle style,
  ) {
    var widest = 0.0;
    final TextStyle label = TabContent.labelStyle(style, selected: true);
    for (final GlassTabItem item in items) {
      final painter = TextPainter(
        text: TextSpan(text: item.label, style: label),
        textDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
      )..layout();
      widest = math.max(widest, painter.width);
      painter.dispose();
    }
    return widest;
  }

  @override
  Widget build(BuildContext context) {
    // The tabs in slot order.
    final List<GlassTabItem> items = <GlassTabItem>[
      for (var slot = 0; slot < widget.items.length; slot++)
        widget.items[_slot(slot)],
    ];
    final GlassTabBarStyle style = widget._style;
    _contentDark = _appearance.isDark;
    Widget layer(GlassTabItem item, TabLayer layer) => widget.debugHideContent
        ? const SizedBox()
        : ExcludeSemantics(
            child: TabContent(
              item: item,
              layer: layer,
              style: style,
              dark: _contentDark,
            ),
          );
    return SizedBox(
      height: GlassTabBar.heightWith(widget.padding),
      child: _TabBarLayout(
        physics: _physics,
        appearance: _appearance,
        frame: _frame,
        onPointer: _handlePointer,
        debugView: widget.debugView,
        shareBackdrop: widget.debugShareBackdrop,
        inspector: widget.debugInspector,
        optics: widget.debugOptics,
        lift: widget.debugLift,
        devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
        contentDark: _contentDark,
        hasOriginal: anyOriginal(items, style),
        labelWidth: _widestLabel(context, items, style),
        tints: <Color>[
          for (final GlassTabItem item in items)
            GlassTabBarStyle.resolve(
              item.selectedColor ??
                  widget.selectedColor ??
                  GlassTabBarStyle.systemBlue,
              dark: _contentDark,
            ),
        ],
        glass: (widget.glass ?? const GlassDecoration()).withColor(
          widget.glassColor,
        ),
        indicator: (widget.indicator ?? const GlassDecoration()).withColor(
          widget.indicatorColor,
        ),
        lens: (widget.lens ?? const GlassDecoration()).withColor(
          widget.lensColor,
        ),
        textDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
        padding:
            (widget.padding ?? const EdgeInsets.all(GlassTabBarPhysics.inset))
                .resolve(Directionality.maybeOf(context) ?? TextDirection.ltr),
        // One child per tab and layer: each layer's tabs in slot order.
        children: <Widget>[
          for (var slot = 0; slot < items.length; slot++)
            Semantics(
              button: true,
              selected: _slot(slot) == widget.selectedIndex,
              label: items[slot].label,
              value: items[slot].badge,
              onTap: () => widget.onSelected(_slot(slot)),
              child: layer(items[slot], TabLayer.values[0]),
            ),
          for (final TabLayer l in TabLayer.values.skip(1))
            for (final GlassTabItem item in items) layer(item, l),
        ],
      ),
    );
  }
}

class _Frame extends ChangeNotifier {
  void notify() => notifyListeners();
}

class _TabBarLayout extends MultiChildRenderObjectWidget {
  const _TabBarLayout({
    required this.physics,
    required this.appearance,
    required this.frame,
    required this.onPointer,
    required this.debugView,
    required this.shareBackdrop,
    required this.inspector,
    required this.optics,
    required this.lift,
    required this.devicePixelRatio,
    required this.contentDark,
    required this.hasOriginal,
    required this.labelWidth,
    required this.tints,
    required this.glass,
    required this.indicator,
    required this.lens,
    required this.textDirection,
    required this.padding,
    required super.children,
  });

  final GlassTabBarPhysics physics;
  final GlassAppearance appearance;
  final Listenable frame;
  final ValueChanged<PointerEvent> onPointer;
  final GlassTabBarDebugView debugView;
  final bool shareBackdrop;
  final Rect? inspector;
  final int optics;
  final double? lift;
  final double devicePixelRatio;
  final bool contentDark;
  final bool hasOriginal;
  final double labelWidth;
  final List<Color> tints;
  final GlassDecoration glass;
  final GlassDecoration indicator;
  final GlassDecoration lens;
  final TextDirection textDirection;
  final EdgeInsets padding;

  @override
  RenderGlassTabBar createRenderObject(BuildContext context) {
    return RenderGlassTabBar(
      physics: physics,
      appearance: appearance,
      frame: frame,
      onPointer: onPointer,
      debugView: debugView,
      shareBackdrop: shareBackdrop,
      inspector: inspector,
      optics: optics,
      lift: lift,
      devicePixelRatio: devicePixelRatio,
      contentDark: contentDark,
      hasOriginal: hasOriginal,
      labelWidth: labelWidth,
      tints: tints,
      glass: glass,
      indicator: indicator,
      lens: lens,
      textDirection: textDirection,
      padding: padding,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderGlassTabBar renderObject,
  ) {
    renderObject
      ..onPointer = onPointer
      ..debugView = debugView
      ..shareBackdrop = shareBackdrop
      ..inspector = inspector
      ..optics = optics
      ..lift = lift
      ..devicePixelRatio = devicePixelRatio
      ..contentDark = contentDark
      ..hasOriginal = hasOriginal
      ..labelWidth = labelWidth
      ..tints = tints
      ..glass = glass
      ..indicator = indicator
      ..lens = lens
      ..textDirection = textDirection
      ..padding = padding;
  }
}

class _TabParentData extends ContainerBoxParentData<RenderBox> {}

/// Lays out a [GlassTabBar]'s tabs (each four times: a child for each
/// [TabLayer]), takes its touches, and paints the glass and the tabs where
/// [GlassTabBarPhysics] puts them.
///
/// The glass is two passes over one backdrop capture. The bar's pass comes
/// first and takes the capture: everything behind the bar, before any of its
/// glass. The lens's pass comes after the tabs and reads that same capture
/// (a shared [BackdropKey]), so it can reach content far outside itself but
/// never sees the bar's glass, the tabs, or itself. The tabs under the lens
/// are not painted here but lifted into it: the lens's shader draws them
/// from an atlas of the tabs in the selected style, grown and lensed.
class RenderGlassTabBar extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _TabParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _TabParentData> {
  RenderGlassTabBar({
    required this._physics,
    required this._appearance,
    required this._frame,
    required this.onPointer,
    required this._debugView,
    required this._shareBackdrop,
    required this._inspector,
    this._optics = GlassTabBarOptics.all,
    this._lift,
    required this._devicePixelRatio,
    this._contentDark = false,
    this._hasOriginal = false,
    this._labelWidth = 0,
    this._tints = const <Color>[],
    this._glass = const GlassDecoration(),
    this._indicator = const GlassDecoration(),
    this._lens = const GlassDecoration(),
    this._textDirection = TextDirection.ltr,
    this._padding = const EdgeInsets.all(GlassTabBarPhysics.inset),
  });

  final GlassTabBarPhysics _physics;
  final GlassAppearance _appearance;
  final Listenable _frame;
  ValueChanged<PointerEvent> onPointer;

  GlassTabBarDebugView get debugView => _debugView;
  GlassTabBarDebugView _debugView;
  set debugView(GlassTabBarDebugView value) {
    if (value != _debugView) {
      _debugView = value;
      markNeedsCompositingBitsUpdate();
      markNeedsPaint();
    }
  }

  bool get shareBackdrop => _shareBackdrop;
  bool _shareBackdrop;
  set shareBackdrop(bool value) {
    if (value != _shareBackdrop) {
      _shareBackdrop = value;
      markNeedsPaint();
    }
  }

  Rect? get inspector => _inspector;
  Rect? _inspector;
  set inspector(Rect? value) {
    if (value != _inspector) {
      _inspector = value;
      markNeedsPaint();
    }
  }

  /// The optical stages drawn: a [GlassTabBarOptics] mask.
  int get optics => _optics;
  int _optics;
  set optics(int value) {
    if (value != _optics) {
      _optics = value;
      markNeedsPaint();
    }
  }

  /// The lift progress the optics are drawn at, when not the lens's own.
  double? get lift => _lift;
  double? _lift;
  set lift(double? value) {
    if (value != _lift) {
      _lift = value;
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

  /// Whether the tabs are drawn for the dark appearance: the selected tint
  /// is mixed in as UIKit's dark matrix does.
  bool get contentDark => _contentDark;
  bool _contentDark;
  set contentDark(bool value) {
    if (value != _contentDark) {
      _contentDark = value;
      markNeedsPaint();
    }
  }

  /// Whether any tab has content drawn as it is (badges, original-color
  /// icons, a set unselected color): the shader reads it only then.
  bool get hasOriginal => _hasOriginal;
  bool _hasOriginal;
  set hasOriginal(bool value) {
    if (value != _hasOriginal) {
      _hasOriginal = value;
      markNeedsPaint();
    }
  }

  /// The widest label's width, which sizes a bar of up to three tabs.
  double get labelWidth => _labelWidth;
  double _labelWidth;
  set labelWidth(double value) {
    if (value != _labelWidth) {
      _labelWidth = value;
      markNeedsLayout();
    }
  }

  /// Each tab's selected color (in slot order), resolved for the appearance:
  /// the shader reads it from a strip under the content atlas, so a
  /// template's own colors never matter, as in UIKit.
  List<Color> get tints => _tints;
  List<Color> _tints;
  set tints(List<Color> value) {
    if (!listEquals(value, _tints)) {
      _tints = value;
      markNeedsPaint();
    }
  }

  /// The decorations of the platter, the resting selection and the lens
  /// (see [GlassTabBar.glass]).
  GlassDecoration get glass => _glass;
  GlassDecoration _glass;
  set glass(GlassDecoration value) {
    if (value != _glass) {
      _glass = value;
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

  GlassDecoration get lens => _lens;
  GlassDecoration _lens;
  set lens(GlassDecoration value) {
    if (value != _lens) {
      _lens = value;
      markNeedsPaint();
    }
  }

  /// Space inside the bar around its tabs (see [GlassTabBar.padding]).
  EdgeInsets get padding => _padding;
  EdgeInsets _padding;
  set padding(EdgeInsets value) {
    if (value != _padding) {
      _padding = value;
      markNeedsLayout();
    }
  }

  // Each tab's content is laid out in a box of UIKit's 62pt bar, its pill
  // 4pt in from its top and bottom; the padding moves it down by this much.
  static const double _rowHeight =
      GlassTabBarPhysics.tabHeight + 2 * GlassTabBarPhysics.inset;
  double get _rowTop => _padding.top - GlassTabBarPhysics.inset;

  /// For gradients' directional alignments.
  TextDirection get textDirection => _textDirection;
  TextDirection _textDirection;
  set textDirection(TextDirection value) {
    if (value != _textDirection) {
      _textDirection = value;
      markNeedsPaint();
    }
  }

  GlassTint _tint(Color? color, GlassFill fill) {
    final Color? resolved = color == null
        ? null
        : GlassTabBarStyle.resolve(color, dark: _contentDark);
    return fill == GlassFill.paint
        ? GlassTint.paint(resolved)
        : GlassTint(resolved, darkAppearance: _contentDark);
  }

  // A decoration's tint over [shape] (capture pixels): at its gradient's
  // start and end, the gradient's axis, and whether it is painted rather
  // than tinted; a color is both ends at once.
  (GlassTint, GlassTint, Offset, Offset, bool) _decorationTint(
    GlassDecoration decoration,
    Rect shape,
  ) {
    final GlassFill fill = decoration.fill;
    final bool paint = fill == GlassFill.paint;
    final LinearGradient? gradient = decoration.gradient;
    if (gradient == null || gradient.colors.isEmpty) {
      final GlassTint t = _tint(decoration.color, fill);
      return (t, t, Offset.zero, Offset.zero, paint);
    }
    return (
      _tint(gradient.colors.first, fill),
      _tint(gradient.colors.last, fill),
      gradient.begin.resolve(_textDirection).withinRect(shape),
      gradient.end.resolve(_textDirection).withinRect(shape),
      paint,
    );
  }

  ui.FragmentShader? _fieldShader;

  // One shader per pass: a shader image filter reads its uniforms only when
  // it is composited, after all passes have been painted.
  final List<_BackdropUniforms> _passes = <_BackdropUniforms>[];

  // One capture for the bar and the lens (and the inspector); a second key
  // only for the comparison where the lens reads the bar's glass.
  final BackdropKey _sharedCapture = BackdropKey();
  final BackdropKey _lensOwnCapture = BackdropKey();

  final LayerHandle<ClipRectLayer> _barClip = LayerHandle<ClipRectLayer>();
  final LayerHandle<BackdropFilterLayer> _barPass =
      LayerHandle<BackdropFilterLayer>();
  final LayerHandle<ClipRectLayer> _lensClip = LayerHandle<ClipRectLayer>();
  final LayerHandle<BackdropFilterLayer> _lensPass =
      LayerHandle<BackdropFilterLayer>();
  final LayerHandle<ClipRectLayer> _inspectorClip =
      LayerHandle<ClipRectLayer>();
  final LayerHandle<BackdropFilterLayer> _inspectorPass =
      LayerHandle<BackdropFilterLayer>();

  bool get _drawsGlass =>
      (_debugView == GlassTabBarDebugView.none ||
          _debugView == GlassTabBarDebugView.sampling) &&
      ui.ImageFilter.isShaderFilterSupported;

  @override
  bool get alwaysNeedsCompositing => _drawsGlass;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _TabParentData) {
      child.parentData = _TabParentData();
    }
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _frame.addListener(_onFrame);
  }

  @override
  void detach() {
    _frame.removeListener(_onFrame);
    super.detach();
  }

  // A new animation frame repaints the glass, not the tabs' content.
  bool _repaintingFrame = false;
  void _onFrame() {
    _repaintingFrame = true;
    markNeedsPaint();
    _repaintingFrame = false;
  }

  @override
  void markNeedsPaint() {
    // Anything else (a tab's content changing, a new layout, a setting) may
    // change what the lens shows of the tabs.
    if (!_repaintingFrame) {
      _contentDirty = true;
    }
    super.markNeedsPaint();
  }

  @override
  void dispose() {
    _contentAtlas?.dispose();
    _noContent?.dispose();
    _fieldShader?.dispose();
    for (final _BackdropUniforms u in _passes) {
      u.shader.dispose();
    }
    _clearGlassLayers();
    super.dispose();
  }

  void _clearGlassLayers() {
    _barClip.layer = null;
    _barPass.layer = null;
    _lensClip.layer = null;
    _lensPass.layer = null;
    _inspectorClip.layer = null;
    _inspectorPass.layer = null;
    _glowClip.layer = null;
  }

  int get _tabCount => childCount ~/ tabLayerCount;

  @override
  void performLayout() {
    _contentDirty = true;
    final int count = _tabCount;
    size = constraints.constrain(
      Size(
        GlassTabBarPhysics.naturalWidth(
              count,
              _labelWidth,
              horizontal: _padding.horizontal,
            ) ??
            (constraints.hasBoundedWidth ? constraints.maxWidth : 398),
        GlassTabBarPhysics.tabHeight + _padding.vertical,
      ),
    );
    if (count == 0) {
      return;
    }
    _physics.layout(size, count, padding: _padding);
    final double width = _physics.pillWidth;
    final tight = BoxConstraints.tight(Size(width, _rowHeight));
    var i = 0;
    RenderBox? child = firstChild;
    while (child != null) {
      child.layout(tight);
      (child.parentData! as _TabParentData).offset = Offset(
        _physics.tabCenter(i % count) - width / 2,
        _rowTop,
      );
      child = childAfter(child);
      i++;
    }
  }

  @override
  bool hitTestSelf(Offset position) => size.contains(position);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      false;

  @override
  void handleEvent(PointerEvent event, BoxHitTestEntry entry) {
    onPointer(event);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_tabCount == 0) {
      return;
    }
    final ui.FragmentProgram? program = GlassTabBar._backdrop.program;
    if (_drawsGlass && program == null) {
      // The shaders are loading (GlassTabBar.precache): nothing for a frame
      // or two, rather than the flat fallback.
      _clearGlassLayers();
      return;
    }
    if (!_drawsGlass || program == null) {
      _clearGlassLayers();
      _paintField(context.canvas, offset);
      context.pushTransform(
        needsCompositing,
        offset,
        _physics.platterTransform,
        _paintTabs,
      );
      return;
    }
    _paintGlass(context, offset, program);
  }

  // --------------------------------------------------------------- the glass

  void _paintGlass(
    PaintingContext context,
    Offset offset,
    ui.FragmentProgram program,
  ) {
    final bool diagnostic = _debugView == GlassTabBarDebugView.sampling;
    while (_passes.length < 3) {
      _passes.add(_BackdropUniforms(program.fragmentShader()));
    }
    final _CaptureSpace space = _CaptureSpace(
      getTransformTo(null),
      _devicePixelRatio,
    );
    final Rect platter = _physics.platterRect;
    final Rect lens = _physics.lensRect;
    final Offset? touch = _physics.touch;

    // The same geometry for every pass, in capture pixels.
    final Rect platterPixels = space.rect(platter);
    final Rect lensPixels = space.rect(lens);
    final Offset finger = touch == null ? Offset.zero : space.point(touch);
    final Rect inspector = _inspectorRect;
    final Rect inspectorPixels = space.rect(inspector);
    final Rect window = space.rect(
      Rect.fromCenter(
        center: lens.center,
        width: inspector.width / _inspectorZoom,
        height: inspector.height / _inspectorZoom,
      ),
    );

    // The glass's optics are in its own points: the lens is drawn scaled by
    // the platter and by its flex, the platter by its swell and stretch.
    final double platterScale = math.sqrt(
      _physics.platterScaleX * _physics.platterScaleY,
    );
    final Size flex = _physics.flexScale;
    final double lensScale = platterScale * math.sqrt(flex.width * flex.height);

    // The tabs in the selected style, which the lens draws itself.
    final ui.Image atlas = _ensureContentAtlas();
    final Offset barOrigin = space.point(Offset.zero);
    final Offset platterCenter = size.center(Offset.zero);
    final Offset drift = _physics.platterDrift;
    final int count = _tabCount;

    // The fingertip glow, for the lens's view of it: a gaussian of the
    // blurred disk's peak and volume.
    final Offset? glowCenter = _physics.glowCenter;
    final double glowAlpha = _optics & GlassTabBarOptics.press != 0
        ? _physics.glowAlpha
        : 0;
    final double glowRadius = space.pointSize * _physics.glowSize / 2;
    final double glowSigma = space.pointSize * _physics.glowSigma;
    final double glowPeak =
        1 - math.exp(-glowRadius * glowRadius / (2 * glowSigma * glowSigma));
    final double glowVariance = glowRadius * glowRadius / (2 * glowPeak);
    final Offset glowPixels = glowCenter == null
        ? Offset.zero
        : space.point(glowCenter);

    // The appearance's color inputs.
    final GlassAppearance appearance = _appearance;
    final (double, double, double, double) face = appearance.face;
    final double shadow = appearance.shadow;
    final (double, double, double) platterRim = appearance.platterRim;
    final (double, double, double) lensRim = appearance.lensRim;
    final (double, double, double) pill = appearance.pill;
    final (double, double) symbol = appearance.symbol;
    final glassTint = _decorationTint(_glass, platterPixels);
    final restTint = _decorationTint(_indicator, lensPixels);
    final lensTint = _decorationTint(_lens, lensPixels);

    ui.ImageFilter passFilter(int pass) {
      final _BackdropUniforms u = _passes[pass]
        ..pass.set(
          pass.toDouble(),
          diagnostic ? 1 : 0,
          space.pointSize,
          _ovalization,
        )
        ..platter.setRect(platterPixels)
        ..lens.setRect(lensPixels)
        ..optics.set(
          _lift ?? _physics.liftProgress,
          lensScale,
          platterScale,
          _optics.toDouble(),
        )
        ..touch.set(finger.dx, finger.dy, touch == null ? 0 : 1, _physics.press)
        ..inspector.set(
          inspectorPixels.left,
          inspectorPixels.top,
          inspectorPixels.width,
          inspectorPixels.height,
        )
        ..window.set(window.left, window.top, window.width, window.height)
        // The atlas's size as rendered: whole pixels, so at a fractional
        // pixel ratio a little more than the bounds it was drawn in.
        ..content.set(
          barOrigin.dx,
          barOrigin.dy,
          atlas.width / _devicePixelRatio,
          atlas.height / _devicePixelRatio,
        )
        ..tabs.set(
          _physics.tabCenter(0),
          count > 1 ? _physics.tabCenter(1) - _physics.tabCenter(0) : 0,
          count.toDouble(),
          _atlasPitch,
        )
        ..platterTransform.set(
          platterCenter.dx,
          platterCenter.dy,
          drift.dx,
          drift.dy,
        )
        ..platterScale.set(
          _physics.platterScaleX,
          _physics.platterScaleY,
          _rowHeight,
          _atlasSlot,
        )
        ..glow.set(
          glowPixels.dx,
          glowPixels.dy,
          1 / (2 * glowVariance),
          glowCenter == null ? 0 : glowAlpha * glowPeak,
        )
        ..face.set(face.$1, face.$2, face.$3, face.$4)
        // A decoration's own shadows replace UIKit's.
        ..rim.set(
          platterRim.$1,
          platterRim.$2,
          platterRim.$3,
          _glass.shadows == null ? shadow : 0,
        )
        ..lensRim.set(lensRim.$1, lensRim.$2, lensRim.$3, symbol.$2)
        ..pill.set(pill.$1, pill.$2, pill.$3, symbol.$1)
        // UIKit's selected matrix: half of the glass below plus the tint
        // (held in the atlas's color), less half a unit in the light
        // appearance.
        // .y: where the tabs' content rows start in the bar.
        ..selected.set(
          _contentDark ? 0 : -0.5,
          _rowTop,
          0,
          _hasOriginal ? 1 : 0,
        )
        ..setTints(glassTint, restTint, lensTint);
      u.shader.setImageSampler(1, atlas);
      return ui.ImageFilter.shader(u.shader);
    }

    // The decorations' shadows, with the glass's shapes as drawn: the
    // selection's fade as the lens lifts (the resting selection with the
    // lift, the lens's material four times as fast, as UIKit's).
    final RRect platterShape = RRect.fromRectAndRadius(
      platter.shift(offset),
      Radius.circular(platter.shortestSide / 2),
    );
    final RRect lensShape = RRect.fromRectAndRadius(
      lens.shift(offset),
      Radius.circular(lens.shortestSide / 2),
    );
    final double lift = _lift ?? _physics.liftProgress;
    final double resting = (1 - lift).clamp(0.0, 1.0);
    final double lifted = (4 * lift).clamp(0.0, 1.0);
    // The canvas between the passes' layers.
    Canvas canvas() => context.canvas;

    // The glass's drop shadows go under it, into the backdrop it captures.
    if (!diagnostic) {
      _paintShadows(canvas(), platterShape, _glass.shadows, 1);
    }

    // Pass 1, the bar: takes the capture, before any glass. Its shadows
    // reach past the platter.
    final bool shadows = _optics & GlassTabBarOptics.shadow != 0 && !diagnostic;
    _barClip.layer = context.pushClipRect(
      needsCompositing,
      offset,
      platter.inflate(shadows ? _shadowMargin : 2),
      (PaintingContext context, Offset offset) {
        final BackdropFilterLayer layer =
            (_barPass.layer ??= BackdropFilterLayer())
              ..filter = passFilter(0)
              ..backdropKey = _sharedCapture;
        context.pushLayer(layer, _paintNothing, offset);
      },
      oldLayer: _barClip.layer,
    );

    // (The bar's shader draws the tabs outside the lens, and the lens's
    // shader those in it, from the content atlas: UIKit colors them from
    // the glass below them.)

    // The fingertip glow, over the platter and its tabs: under the lens,
    // whose shader sees it through its optics.
    if (!diagnostic) {
      _paintInnerShadows(canvas(), platterShape, _glass.innerShadows, 1);
      _paintShadows(canvas(), lensShape, _indicator.shadows, resting);
      _paintShadows(canvas(), lensShape, _lens.shadows, lifted);
    }
    _paintGlow(context, offset, platter);

    // Pass 2, the lens: the same capture, with the tabs under it lifted into
    // it (drawn by its shader from the content atlas).
    final BackdropKey lensCapture = _shareBackdrop
        ? _sharedCapture
        : _lensOwnCapture;
    _lensClip.layer = context.pushClipRect(
      needsCompositing,
      offset,
      lens.inflate(shadows ? _lensShadowMargin : 2),
      (PaintingContext context, Offset offset) {
        final BackdropFilterLayer layer =
            (_lensPass.layer ??= BackdropFilterLayer())
              ..filter = passFilter(1)
              ..backdropKey = lensCapture;
        context.pushLayer(layer, _paintNothing, offset);
      },
      oldLayer: _lensClip.layer,
    );

    if (!diagnostic) {
      _paintInnerShadows(canvas(), lensShape, _indicator.innerShadows, resting);
      _paintInnerShadows(canvas(), lensShape, _lens.innerShadows, lifted);
      _inspectorClip.layer = null;
      _inspectorPass.layer = null;
      return;
    }

    // The inspector reads whatever the lens reads.
    _inspectorClip.layer = context.pushClipRect(
      needsCompositing,
      offset,
      inspector,
      (PaintingContext context, Offset offset) {
        final BackdropFilterLayer layer =
            (_inspectorPass.layer ??= BackdropFilterLayer())
              ..filter = passFilter(2)
              ..backdropKey = lensCapture;
        context.pushLayer(layer, (PaintingContext context, Offset offset) {
          _paintInspectorLabels(context.canvas, offset + inspector.topLeft);
        }, offset);
      },
      oldLayer: _inspectorClip.layer,
    );

    // The same field and finger in layout coordinates, as thin dark lines
    // down the middle of the shaders' colored ones.
    _paintLayoutCheck(context.canvas, offset);
  }

  static void _paintNothing(PaintingContext context, Offset offset) {}

  static Paint _shadowPaint(BoxShadow shadow, double opacity) {
    final paint = Paint()
      ..color = shadow.color.withValues(alpha: shadow.color.a * opacity);
    if (shadow.blurSigma > 0) {
      paint.maskFilter = MaskFilter.blur(BlurStyle.normal, shadow.blurSigma);
    }
    return paint;
  }

  // How far [shadow] reaches past its shape.
  static double _reach(BoxShadow shadow) =>
      2 * shadow.blurRadius +
      shadow.spreadRadius.abs() +
      shadow.offset.distance +
      2;

  // Drop shadows of [shape], around it only: the glass shows what is under
  // it, a shadow there included.
  static void _paintShadows(
    Canvas canvas,
    RRect shape,
    List<BoxShadow>? shadows,
    double opacity,
  ) {
    if (shadows == null || shadows.isEmpty || opacity <= 0) {
      return;
    }
    final double reach = shadows.map(_reach).reduce(math.max);
    canvas
      ..save()
      ..clipPath(
        Path()
          ..fillType = PathFillType.evenOdd
          ..addRect(shape.outerRect.inflate(reach))
          ..addRRect(shape),
      );
    for (final BoxShadow shadow in shadows) {
      canvas.drawRRect(
        shape.inflate(shadow.spreadRadius).shift(shadow.offset),
        _shadowPaint(shadow, opacity),
      );
    }
    canvas.restore();
  }

  // Shadows cast inward from [shape]'s edge, over it, as inset shadows: the
  // shape's outside, its edge moved by the offset and in by the spread,
  // blurred into it.
  static void _paintInnerShadows(
    Canvas canvas,
    RRect shape,
    List<BoxShadow>? shadows,
    double opacity,
  ) {
    if (shadows == null || shadows.isEmpty || opacity <= 0) {
      return;
    }
    canvas
      ..save()
      ..clipRRect(shape);
    for (final BoxShadow shadow in shadows) {
      canvas.drawPath(
        Path()
          ..fillType = PathFillType.evenOdd
          ..addRect(shape.outerRect.inflate(_reach(shadow)))
          ..addRRect(shape.deflate(shadow.spreadRadius).shift(shadow.offset)),
        _shadowPaint(shadow, opacity),
      );
    }
    canvas.restore();
  }

  // How far the platter's shadow reaches past it: 39pt past its outline
  // moved 8pt down.
  static const double _shadowMargin = 48;

  // How far the lens's shadow reaches past it: its outline moved 7pt down,
  // and 9.2pt past that.
  static const double _lensShadowMargin = 18;

  // UIKit's LittleGlowView: a white disk under the finger, blurred, clipped
  // to the platter.
  void _paintGlow(PaintingContext context, Offset offset, Rect platter) {
    final Offset? center = _physics.glowCenter;
    final double alpha = _physics.glowAlpha;
    if (_optics & GlassTabBarOptics.press == 0 ||
        center == null ||
        alpha < 1 / 512) {
      _glowClip.layer = null;
      return;
    }
    _glowClip.layer = context.pushClipRRect(
      needsCompositing,
      offset,
      platter,
      RRect.fromRectAndRadius(
        platter,
        Radius.circular(platter.shortestSide / 2),
      ),
      (PaintingContext context, Offset offset) {
        context.canvas.drawCircle(
          offset + center,
          _physics.glowSize / 2,
          Paint()
            ..color = Color.fromRGBO(255, 255, 255, alpha)
            ..maskFilter = MaskFilter.blur(
              BlurStyle.normal,
              _physics.glowSigma,
            ),
        );
      },
      oldLayer: _glowClip.layer,
    );
  }

  final LayerHandle<ClipRRectLayer> _glowClip = LayerHandle<ClipRRectLayer>();

  // UIKit's gradientOvalization for the glass's distance field.
  static const double _ovalization = 0.5;
  static const double _inspectorZoom = 2;

  Rect get _inspectorRect =>
      _inspector ?? Rect.fromLTWH(0, -24 - 300, size.width, 300);

  void _paintInspectorLabels(Canvas canvas, Offset origin) {
    final painter = TextPainter(
      text: TextSpan(
        text:
            '${_shareBackdrop ? 'shared capture' : "lens's own capture, taken after the bar's glass"}'
            ', ×2: yellow bar, cyan lens, '
            'pink sampling region, orange sampled band',
        style: const TextStyle(fontSize: 10, color: Color(0xFFFFFFFF)),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: _inspectorRect.width - 12);
    canvas.drawRect(
      Rect.fromLTWH(
        origin.dx,
        origin.dy,
        painter.width + 12,
        painter.height + 8,
      ),
      Paint()..color = const Color(0xB0000000),
    );
    painter.paint(canvas, origin + const Offset(6, 4));
    painter.dispose();
  }

  void _paintLayoutCheck(Canvas canvas, Offset offset) {
    final double hair = 1 / _devicePixelRatio;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = hair
      ..color = const Color(0xFF000000);
    for (final Rect r in <Rect>[_physics.platterRect, _physics.lensRect]) {
      final Rect inset = r.deflate(0.75).shift(offset);
      canvas.drawRRect(
        RRect.fromRectAndRadius(inset, Radius.circular(inset.shortestSide / 2)),
        line,
      );
    }
    final Offset? touch = _physics.touch;
    if (touch != null) {
      final Offset t = touch + offset;
      canvas
        ..drawLine(t - const Offset(10, 0), t + const Offset(10, 0), line)
        ..drawLine(t - const Offset(0, 10), t + const Offset(0, 10), line);
    }
  }

  // -------------------------------------------------------- the lifted content

  // The selected-style tabs, one per slot of an image, for the lens's shader
  // to grow and lens each about its own center (as UIKit scales its
  // selected tab buttons and lenses them through the lens). Rendered again
  // only when the tabs or their layout change, not every animation frame.
  ui.Image? _contentAtlas;
  ui.Image? _noContent;
  bool _contentDirty = true;

  // Room around each tab for labels wider than the pill.
  static const double _atlasMargin = 12;
  double get _atlasSlot => _physics.pillWidth + 2 * _atlasMargin;
  double get _atlasPitch => _atlasSlot + 2;

  ui.Image _ensureContentAtlas() {
    final int count = _tabCount;
    if (count == 0 || size.isEmpty) {
      return _noContent ??= _emptyImage();
    }
    if (_contentDirty || _contentAtlas == null) {
      _contentDirty = false;
      // A row for each layer (TabLayer.row), a slot in it for each tab;
      // under them, a point high strip of each tab's selected color.
      final Rect bounds = Rect.fromLTWH(
        0,
        0,
        count * _atlasPitch,
        tabLayerCount * _rowHeight + 1,
      );
      final layer = OffsetLayer();
      final context = _AtlasContext(layer, bounds);
      var i = 0;
      RenderBox? child = firstChild;
      while (child != null) {
        context.paintChild(
          child,
          Offset(
            (i % count) * _atlasPitch + _atlasMargin,
            TabLayer.values[i ~/ count].row * _rowHeight,
          ),
        );
        child = childAfter(child);
        i++;
      }
      for (var slot = 0; slot < count && slot < _tints.length; slot++) {
        context.canvas.drawRect(
          Rect.fromLTWH(
            slot * _atlasPitch,
            tabLayerCount * _rowHeight,
            _atlasPitch,
            1,
          ),
          Paint()..color = _tints[slot].withValues(alpha: 1),
        );
      }
      context.finish();
      _contentAtlas?.dispose();
      _contentAtlas = layer.toImageSync(bounds, pixelRatio: _devicePixelRatio);
      layer.dispose();
    }
    return _contentAtlas!;
  }

  static ui.Image _emptyImage() {
    final recorder = ui.PictureRecorder();
    Canvas(recorder);
    final ui.Picture picture = recorder.endRecording();
    final ui.Image image = picture.toImageSync(1, 1);
    picture.dispose();
    return image;
  }

  // ------------------------------------------------------------ the tab items

  // The tabs, inside the platter: normal outside the lens, selected within
  // it.
  void _paintTabs(PaintingContext context, Offset offset, {bool? inside}) {
    final Rect lens = _physics.lensInPlatter.shift(offset);
    final RRect lensShape = RRect.fromRectAndRadius(
      lens,
      Radius.circular(lens.shortestSide / 2),
    );
    final Rect bounds = (offset & size).inflate(40);
    final int count = _tabCount;
    if (inside != true) {
      final outside = Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(bounds)
        ..addRRect(lensShape);
      context.canvas
        ..save()
        ..clipPath(outside);
      _paintChildren(context, offset, count, selected: false);
      context.canvas.restore();
    }
    if (inside != false) {
      context.canvas
        ..save()
        ..clipRRect(lensShape);
      _paintChildren(context, offset, count, selected: true);
      context.canvas.restore();
    }
  }

  void _paintChildren(
    PaintingContext context,
    Offset offset,
    int count, {
    required bool selected,
  }) {
    var i = 0;
    RenderBox? child = firstChild;
    while (child != null) {
      if (TabLayer.values[i ~/ count].selected == selected) {
        context.paintChild(
          child,
          (child.parentData! as _TabParentData).offset + offset,
        );
      }
      child = childAfter(child);
      i++;
    }
  }

  // ------------------------------------------------ the field, drawn flat

  void _paintField(Canvas canvas, Offset offset) {
    final Rect platter = _physics.platterRect.shift(offset);
    final Rect lens = _physics.lensRect.shift(offset);
    final ui.FragmentProgram? program = GlassTabBar._field.program;
    if (program == null) {
      // Until the shader is in: the same shapes, drawn plainly.
      canvas
        ..drawRRect(
          RRect.fromRectAndRadius(
            platter,
            Radius.circular(platter.shortestSide / 2),
          ),
          Paint()..color = const Color(0xFFD6D6D6),
        )
        ..drawRRect(
          RRect.fromRectAndRadius(lens, Radius.circular(lens.shortestSide / 2)),
          Paint()..color = const Color(0xFFBDBDBD),
        );
      return;
    }
    final ui.FragmentShader shader = _fieldShader ??= program.fragmentShader();
    shader
      ..getUniformVec4('uPlatter').set(
        platter.center.dx,
        platter.center.dy,
        platter.width / 2,
        platter.height / 2,
      )
      ..getUniformVec4(
        'uLens',
      ).set(lens.center.dx, lens.center.dy, lens.width / 2, lens.height / 2)
      ..getUniformVec4('uState').set(
        _physics.clear,
        0.5,
        1 / _devicePixelRatio,
        _debugView == GlassTabBarDebugView.normals ? 1 : 0,
      );
    canvas.drawRect(
      platter.expandToInclude(lens).inflate(2),
      Paint()..shader = shader,
    );
  }
}

/// Maps the bar's layout coordinates to the capture's: physical pixels of
/// the pass the backdrop is captured from (the root pass, unless an
/// ancestor draws into its own layer).
class _CaptureSpace {
  _CaptureSpace(this.toRoot, this.devicePixelRatio)
    : pointSize =
          devicePixelRatio *
          (MatrixUtils.transformPoint(toRoot, const Offset(1, 0)) -
                  MatrixUtils.transformPoint(toRoot, Offset.zero))
              .distance;

  final Matrix4 toRoot;
  final double devicePixelRatio;

  /// One layout point, in capture pixels.
  final double pointSize;

  Offset point(Offset p) =>
      MatrixUtils.transformPoint(toRoot, p) * devicePixelRatio;

  Rect rect(Rect r) {
    final Rect g = MatrixUtils.transformRect(toRoot, r);
    return Rect.fromLTRB(
      g.left * devicePixelRatio,
      g.top * devicePixelRatio,
      g.right * devicePixelRatio,
      g.bottom * devicePixelRatio,
    );
  }
}

/// Named bindings into the backdrop shader.
class _BackdropUniforms {
  _BackdropUniforms(this.shader)
    : pass = shader.getUniformVec4('uPass'),
      platter = shader.getUniformVec4('uPlatter'),
      lens = shader.getUniformVec4('uLens'),
      optics = shader.getUniformVec4('uOptics'),
      touch = shader.getUniformVec4('uTouch'),
      inspector = shader.getUniformVec4('uInspector'),
      window = shader.getUniformVec4('uWindow'),
      content = shader.getUniformVec4('uContent'),
      tabs = shader.getUniformVec4('uTabs'),
      platterTransform = shader.getUniformVec4('uPlatterXf'),
      platterScale = shader.getUniformVec4('uPlatterS'),
      glow = shader.getUniformVec4('uGlow'),
      face = shader.getUniformVec4('uFace'),
      rim = shader.getUniformVec4('uRim'),
      lensRim = shader.getUniformVec4('uLensRim'),
      pill = shader.getUniformVec4('uPill'),
      glassTint = _tintSlots(shader, 0),
      restTint = _tintSlots(shader, 1),
      lensTint = _tintSlots(shader, 2),
      selected = shader.getUniformVec4('uSelected');

  final ui.FragmentShader shader;
  final ui.UniformVec4Slot pass;
  final ui.UniformVec4Slot platter;
  final ui.UniformVec4Slot lens;
  final ui.UniformVec4Slot optics;
  final ui.UniformVec4Slot touch;
  final ui.UniformVec4Slot inspector;
  final ui.UniformVec4Slot window;
  final ui.UniformVec4Slot content;
  final ui.UniformVec4Slot tabs;
  final ui.UniformVec4Slot platterTransform;
  final ui.UniformVec4Slot platterScale;
  final ui.UniformVec4Slot glow;
  final ui.UniformVec4Slot face;
  final ui.UniformVec4Slot rim;
  final ui.UniformVec4Slot lensRim;
  final ui.UniformVec4Slot pill;
  final List<ui.UniformVec4Slot> glassTint;
  final List<ui.UniformVec4Slot> restTint;
  final List<ui.UniformVec4Slot> lensTint;
  final ui.UniformVec4Slot selected;

  // A tint's slots: at its gradient's start (over white glass, with its
  // alpha, and over black glass), at its end, and its axis.
  // A tint's five slots in uTints (one array: Metal gives each uniform a
  // buffer of its own, and has 31): at its gradient's start (over white
  // glass, with its alpha, and over black glass), at its end, and its axis.
  static List<ui.UniformVec4Slot> _tintSlots(
    ui.FragmentShader shader,
    int tint,
  ) {
    final ui.UniformArray<ui.UniformVec4Slot> all = shader.getUniformVec4Array(
      'uTints',
    );
    return <ui.UniformVec4Slot>[for (var i = 0; i < 5; i++) all[5 * tint + i]];
  }

  /// The platter's, the resting selection's and the lens's tints, each at its
  /// gradient's start and end, along its axis (capture pixels).
  void setTints(
    (GlassTint, GlassTint, Offset, Offset, bool) glass,
    (GlassTint, GlassTint, Offset, Offset, bool) rest,
    (GlassTint, GlassTint, Offset, Offset, bool) lens,
  ) {
    for (final (
          List<ui.UniformVec4Slot> slots,
          (GlassTint, GlassTint, Offset, Offset, bool) t,
        )
        in <
          (
            List<ui.UniformVec4Slot>,
            (GlassTint, GlassTint, Offset, Offset, bool),
          )
        >[(glassTint, glass), (restTint, rest), (lensTint, lens)]) {
      final (
        GlassTint start,
        GlassTint end,
        Offset from,
        Offset to,
        bool paint,
      ) = t;
      slots[0].set(
        start.bright[0],
        start.bright[1],
        start.bright[2],
        start.alpha,
      );
      // .w: painted rather than tinted.
      slots[1].set(start.dark[0], start.dark[1], start.dark[2], paint ? 1 : 0);
      slots[2].set(end.bright[0], end.bright[1], end.bright[2], end.alpha);
      slots[3].set(end.dark[0], end.dark[1], end.dark[2], 0);
      slots[4].set(from.dx, from.dy, to.dx, to.dy);
    }
  }
}

/// Paints the tabs into a layer of their own, for the content atlas.
class _AtlasContext extends PaintingContext {
  _AtlasContext(super.containerLayer, super.estimatedBounds);

  void finish() => stopRecordingIfNeeded();
}

extension on ui.UniformVec4Slot {
  // A rect as its center and half size.
  void setRect(Rect r) =>
      set(r.center.dx, r.center.dy, r.width / 2, r.height / 2);
}
