part of 'glass.dart';

/// A button of an alert or an action sheet ([showGlassAlert],
/// [showGlassActionSheet]): UIKit's `UIAlertAction`.
@immutable
class GlassAlertAction {
  const GlassAlertAction({
    required this.label,
    this.onPressed,
    this.destructive = false,
    this.cancel = false,
  });

  final String label;

  /// Called when the action is chosen, as the alert goes.
  final VoidCallback? onPressed;

  /// Drawn in red: an action that deletes or cannot be undone.
  final bool destructive;

  /// The action that dismisses without doing anything. UIKit places it
  /// last (leftmost of two side by side); an action sheet's stands apart
  /// below the others, and a tap outside the sheet chooses it.
  final bool cancel;
}

/// A text field of an alert ([showGlassAlert]): UIKit's
/// `UIAlertController.addTextField`, a capsule above the actions.
@immutable
class GlassAlertTextField {
  const GlassAlertTextField({
    this.controller,
    this.placeholder,
    this.obscureText = false,
    this.keyboardType,
  });

  /// Holds the text; read it once the alert completes. The alert makes
  /// its own when null.
  final TextEditingController? controller;

  /// Shown in gray while the field is empty.
  final String? placeholder;

  /// Hides the text, for a password.
  final bool obscureText;

  final TextInputType? keyboardType;
}

/// Shows UIKit's alert (`UIAlertController`, style `.alert`, iOS 26) over
/// the screen: a panel of glass in the middle with [title], [message] and
/// [actions] as capsules, and completes with the action chosen.
///
/// The alert grows in from 1.2 times its size as it fades in over a
/// dimmed screen, and fades away once an action is chosen. Two actions
/// stand side by side; one, or more than two, are stacked. A finger can
/// slide between the actions before letting go, as on UIKit's. Measured on
/// iOS 26.5: the layout, the springs, the glass and its colors.
///
/// [textFields] go between the text and the actions, the first focused;
/// the alert keeps to the middle of the space the keyboard leaves.
Future<GlassAlertAction?> showGlassAlert({
  required BuildContext context,
  String? title,
  String? message,
  List<GlassAlertAction> actions = const <GlassAlertAction>[
    GlassAlertAction(label: 'OK'),
  ],
  List<GlassAlertTextField> textFields = const <GlassAlertTextField>[],
}) {
  assert(actions.isNotEmpty, 'An alert needs an action.');
  final NavigatorState navigator = Navigator.of(context, rootNavigator: true);
  return navigator.push(
    _GlassAlertRoute(
      title: title,
      message: message,
      actions: actions,
      textFields: textFields,
      sheet: false,
      themes: InheritedTheme.capture(from: context, to: navigator.context),
    ),
  );
}

/// Shows UIKit's action sheet (`UIAlertController`, style `.actionSheet`)
/// and completes with the action chosen, or with the cancel action (or
/// null without one) when a tap outside it dismisses it.
///
/// On an iPhone, iOS 26.5 shows an action sheet that no view presents from
/// in the middle of the screen, as its alert ([showGlassAlert]): the same
/// glass, layout and springs; but, unlike an alert, a tap outside it
/// dismisses it.
///
/// With a [source] (the context of the widget it comes from, as UIKit's
/// `popoverPresentationController.sourceView`), it shows as a popover by
/// that widget ([showGlassPopover]): 240pt wide, its actions stacked,
/// without its cancel action (a tap outside chooses it).
Future<GlassAlertAction?> showGlassActionSheet({
  required BuildContext context,
  String? title,
  String? message,
  required List<GlassAlertAction> actions,
  BuildContext? source,
}) {
  assert(actions.isNotEmpty, 'An action sheet needs an action.');
  final NavigatorState navigator = Navigator.of(context, rootNavigator: true);
  return navigator.push(
    _GlassAlertRoute(
      title: title,
      message: message,
      actions: actions,
      textFields: const <GlassAlertTextField>[],
      sheet: true,
      source: source == null ? null : _popoverSource(source, navigator),
      themes: InheritedTheme.capture(from: context, to: navigator.context),
    ),
  );
}

// UIKit's alert (iOS 26.5, iPhone 17 Pro Max, measured).
abstract final class _AlertMetrics {
  static const double width = 320;
  static const double radius = 34;

  // The title and message: 30pt in, the title 22pt down; the actions'
  // capsules 16pt in, 8pt apart, 20.3pt below the text.
  static const double textInset = 30;
  static const double textTop = 22;
  static const double textGap = 7.4;
  // (In an action sheet's popover a pixel more.)
  static const double popoverTextGap = 7.7;
  static const double textBottom = 4.3;
  // A title or message alone.
  static const double soloTop = 21.7;
  static const double soloBottom = 4;
  static const double actionInset = 16;
  static const double actionHeight = 48;
  static const double actionGap = 8;

  // Shown: critically damped, from 1.2 times its size and transparent.
  static const double showResponse = 2 * math.pi / 22.9;
  static const double grow = 0.2;

  // The dim (as the sheet's) eases out (cubic) over 0.275s.
  static const double dim = 0.2;
  static const double darkDim = 0.48;
  static const double dimSeconds = 0.275;

  // The capsules: black at 0.12 on light glass, white at 0.108 on dark;
  // a pressed one at 0.4 of that.
  static const Color lightFill = Color.fromRGBO(0, 0, 0, 0.12);
  static const Color darkFill = Color.fromRGBO(255, 255, 255, 0.108);
  static const double pressedFill = 0.4;

  // Text fields: 48pt rows with the actions' fill, 15pt in, 12pt below
  // the text, together one rounded box (24pt corners) with a 1pt line
  // between rows (15pt in); their text 15pt in; a blue cursor.
  static const double fieldInset = 15;
  static const double fieldTop = 12;
  static const double fieldBottom = 4;
  static const double fieldTextInset = 15;
  static const Color lightSeparator = Color.fromRGBO(0, 0, 0, 0.25);
  static const Color darkSeparator = Color.fromRGBO(255, 255, 255, 0.15);
  static const Color cursor = Color(0xFF426BF2);
  static const Color lightPlaceholder = Color.fromRGBO(60, 60, 67, 0.3);
  static const Color darkPlaceholder = Color.fromRGBO(235, 235, 245, 0.3);

  // The title and message (vibrant on UIKit's glass: as these over it).
  static const Color lightTitle = Color(0xFF000000);
  static const Color darkTitle = Color.fromRGBO(255, 255, 255, 0.95);
  static const Color lightMessage = Color.fromRGBO(0, 0, 0, 0.548);
  static const Color darkMessage = Color.fromRGBO(255, 255, 255, 0.6);
  static const Color lightLabel = Color(0xFF000000);
  static const Color darkLabel = Color(0xFFFFFFFF);
  static const Color lightRed = Color(0xFFFF383C);
  static const Color darkRed = Color(0xFFFF4245);

  static TextStyle titleStyle(Color color) => TextStyle(
    fontSize: 17,
    height: 22 / 17,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.43,
    color: color,
    decoration: TextDecoration.none,
  );

  static TextStyle messageStyle(Color color) => TextStyle(
    fontSize: 15,
    height: 20 / 15,
    letterSpacing: -0.23,
    color: color,
    decoration: TextDecoration.none,
  );

  static TextStyle soloStyle(Color color) => TextStyle(
    fontSize: 17,
    height: 22 / 17,
    letterSpacing: -0.43,
    color: color,
    decoration: TextDecoration.none,
  );

  static TextStyle fieldStyle(Color color) => TextStyle(
    fontSize: 17,
    letterSpacing: -0.43,
    color: color,
    decoration: TextDecoration.none,
  );

  static TextStyle labelStyle(Color color) => TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.43,
    color: color,
    decoration: TextDecoration.none,
  );

  // UIKit's labels keep their font's line height on their first and last
  // lines and space the lines between by the height above.
  static const TextHeightBehavior lines = TextHeightBehavior(
    applyHeightToFirstAscent: false,
    applyHeightToLastDescent: false,
  );
}

class _GlassAlertRoute extends PopupRoute<GlassAlertAction> {
  _GlassAlertRoute({
    required this.title,
    required this.message,
    required this.actions,
    required this.textFields,
    required this.sheet,
    this.source,
    required this.themes,
  });

  final List<GlassAlertTextField> textFields;

  final String? title;
  final String? message;
  final List<GlassAlertAction> actions;
  final CapturedThemes themes;

  // An action sheet: a tap outside it dismisses it.
  final bool sheet;

  // An action sheet's source, in the overlay's coordinates: it shows as a
  // popover by it.
  final Rect? source;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => false;

  @override
  String? get barrierLabel => null;

  // The alert moves on its own springs; these only keep the route for them.
  @override
  Duration get transitionDuration => const Duration(milliseconds: 300);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 300);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => themes.wrap(_GlassAlert(route: this));
}

class _GlassAlert extends StatefulWidget {
  const _GlassAlert({required this.route});

  final _GlassAlertRoute route;

  @override
  State<_GlassAlert> createState() => _GlassAlertState();
}

class _GlassAlertState extends State<_GlassAlert>
    with TickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  Duration? _last;

  final GlassSpring _shown = GlassSpring(
    response: _AlertMetrics.showResponse,
    dampingRatio: 1,
    tolerance: 1e-3,
  );
  // The glass's presence, as drawn (GlassPresence).
  late final AnimationController _presence = AnimationController(
    vsync: this,
    value: 0,
  );

  // Presented from a source: a popover's motion, and its arrow.
  late final _PopoverMotion? _pop = widget.route.source == null
      ? null
      : _PopoverMotion();
  final ValueNotifier<_GlassArrow?> _arrow = ValueNotifier<_GlassArrow?>(null);

  bool _dismissing = false;
  // The dim's easing: its value when it started, and the time since.
  double _dimFrom = 0;
  double _dimTime = 0;

  // The action under the finger, and whether a finger is on the actions.
  int? _highlighted;
  bool _tracking = false;

  List<GlassAlertAction> _ordered = const <GlassAlertAction>[];
  bool _sideBySide = false;

  // The text fields' controllers (the alert's own where none is given).
  late final List<TextEditingController> _controllers = <TextEditingController>[
    for (final GlassAlertTextField f in widget.route.textFields)
      f.controller ?? TextEditingController(),
  ];

  @override
  void initState() {
    super.initState();
    widget.route.animation?.addStatusListener(_routeStatus);
    _shown.target = 1;
    _pop?.show();
    _ticker.start();
  }

  @override
  void dispose() {
    for (var i = 0; i < _controllers.length; i++) {
      if (widget.route.textFields[i].controller == null) {
        _controllers[i].dispose();
      }
    }
    widget.route.animation?.removeStatusListener(_routeStatus);
    _ticker.dispose();
    _presence.dispose();
    _arrow.dispose();
    super.dispose();
  }

  void _routeStatus(AnimationStatus status) {
    if (status == AnimationStatus.reverse) {
      _dismiss(popped: true);
    }
  }

  double get _dimTarget => _dismissing ? 0 : 1;

  double get _dimValue {
    final double t = (_dimTime / _AlertMetrics.dimSeconds).clamp(0.0, 1.0);
    final double eased = Curves.easeOutCubic.transform(t);
    return _dimFrom + (_dimTarget - _dimFrom) * eased;
  }

  void _tick(Duration elapsed) {
    final Duration? last = _last;
    _last = elapsed;
    final _PopoverMotion? pop = _pop;
    if (last != null) {
      final double dt = (elapsed - last).inMicroseconds / 1e6;
      _shown.step(dt);
      pop?.step(dt);
      _dimTime += dt;
    }
    if (pop != null) {
      if (pop.isSettled) {
        pop.settle();
        _ticker.stop();
      }
      _presence.value = pop.shown;
    } else {
      _presence.value = _shown.value.clamp(0.0, 1.0);
      if (_shown.isSettled && _dimTime >= _AlertMetrics.dimSeconds) {
        _shown.snap(_shown.target);
        _presence.value = _shown.value;
        _ticker.stop();
      }
    }
    setState(() {});
  }

  void _wake() {
    if (!_ticker.isActive) {
      _last = null;
      _ticker.start();
    }
  }

  void _dismiss({bool popped = false, GlassAlertAction? chosen}) {
    if (_dismissing) {
      return;
    }
    _dimFrom = _dimValue;
    _dimTime = 0;
    _dismissing = true;
    _highlighted = null;
    _tracking = false;
    _shown.target = 0;
    _pop?.hide();
    _wake();
    if (!popped) {
      final NavigatorState? navigator = widget.route.navigator;
      if (navigator != null && widget.route.isActive) {
        if (widget.route.isCurrent) {
          navigator.pop(chosen);
        } else {
          navigator.removeRoute(widget.route, chosen);
        }
      }
    }
    chosen?.onPressed?.call();
  }

  // An action sheet's tap outside: its cancel action, if it has one.
  void _cancel() {
    _dismiss(
      chosen: widget.route.actions
          .where((GlassAlertAction a) => a.cancel)
          .firstOrNull,
    );
  }

  // ---- Choosing an action: a finger lands on one and may slide to
  // another (or off them all) before it lifts.

  // The action at [p] in the actions' box (its own coordinates), if any.
  int? _actionAt(Offset p, Size box) {
    const double h = _AlertMetrics.actionHeight;
    const double gap = _AlertMetrics.actionGap;
    if (p.dx < 0 || p.dy < 0 || p.dx > box.width || p.dy > box.height) {
      return null;
    }
    if (_sideBySide) {
      final double w = (box.width - gap) / 2;
      return p.dx < w + gap / 2 ? 0 : 1;
    }
    return (p.dy / (h + gap) + gap / 2 / (h + gap)).floor().clamp(
      0,
      _ordered.length - 1,
    );
  }

  void _actionsDown(PointerDownEvent event, Size box) {
    if (_dismissing) {
      return;
    }
    _tracking = true;
    setState(() => _highlighted = _actionAt(event.localPosition, box));
  }

  void _actionsMove(PointerMoveEvent event, Size box) {
    if (!_tracking || _dismissing) {
      return;
    }
    final int? at = _actionAt(event.localPosition, box);
    if (at != _highlighted) {
      setState(() => _highlighted = at);
    }
  }

  void _actionsUp(PointerUpEvent event, Size box) {
    if (!_tracking || _dismissing) {
      return;
    }
    _tracking = false;
    final int? at = _actionAt(event.localPosition, box);
    if (at == null) {
      setState(() => _highlighted = null);
      return;
    }
    _dismiss(chosen: _ordered[at]);
  }

  void _actionsCancel(PointerCancelEvent event) {
    _tracking = false;
    setState(() => _highlighted = null);
  }

  // UIKit's order: two side by side with the cancel action first (left);
  // otherwise stacked with it last.
  void _arrange(TextScaler scaler) {
    final List<GlassAlertAction> actions = widget.route.actions;
    final GlassAlertAction? cancel = actions
        .where((GlassAlertAction a) => a.cancel)
        .firstOrNull;
    final List<GlassAlertAction> rest = <GlassAlertAction>[
      for (final GlassAlertAction a in actions)
        if (!identical(a, cancel)) a,
    ];
    if (widget.route.source != null) {
      // As a popover: stacked, without the cancel action.
      _sideBySide = false;
      _ordered = rest;
      return;
    }
    _sideBySide = actions.length == 2 && _fitsSideBySide(actions, scaler);
    _ordered = _sideBySide
        ? <GlassAlertAction>[?cancel, ...rest]
        : <GlassAlertAction>[...rest, ?cancel];
  }

  bool _fitsSideBySide(List<GlassAlertAction> actions, TextScaler scaler) {
    const double room =
        (_AlertMetrics.width -
                2 * _AlertMetrics.actionInset -
                _AlertMetrics.actionGap) /
            2 -
        2 * 12;
    for (final GlassAlertAction a in actions) {
      final TextPainter p = TextPainter(
        text: TextSpan(
          text: a.label,
          style: _AlertMetrics.labelStyle(const Color(0xFF000000)),
        ),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final double w = p.width;
      p.dispose();
      if (w > room) {
        return false;
      }
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final Size screen = MediaQuery.sizeOf(context);
    final EdgeInsets padding = MediaQuery.paddingOf(context);
    final bool dark =
        MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    _arrange(MediaQuery.textScalerOf(context));
    final _PopoverMotion? pop = _pop;
    final double shown = pop?.shown ?? _shown.value.clamp(0.0, 1.0);
    // Growing in only as it is shown; it fades away at its size.
    final double scale = _dismissing
        ? 1
        : 1 + _AlertMetrics.grow * (1 - _shown.value);
    final double dim =
        (dark ? _AlertMetrics.darkDim : _AlertMetrics.dim) *
        _dimValue.clamp(0.0, 1.0);

    final String? title = widget.route.title;
    final String? message = widget.route.message;
    final Color fill = dark ? _AlertMetrics.darkFill : _AlertMetrics.lightFill;
    final Color label = dark
        ? _AlertMetrics.darkLabel
        : _AlertMetrics.lightLabel;
    final Color red = dark ? _AlertMetrics.darkRed : _AlertMetrics.lightRed;

    Color faded(Color c) => c.withValues(alpha: c.a * shown);

    final Color titleColor = faded(
      dark ? _AlertMetrics.darkTitle : _AlertMetrics.lightTitle,
    );
    // A title or a message alone is centered, in the actions' font.
    final String? only = title == null
        ? message
        : message == null
        ? title
        : null;
    final Widget? text = title == null && message == null
        ? null
        : Padding(
            padding: EdgeInsets.fromLTRB(
              _AlertMetrics.textInset,
              only != null ? _AlertMetrics.soloTop : _AlertMetrics.textTop,
              _AlertMetrics.textInset,
              only != null
                  ? _AlertMetrics.soloBottom
                  : _AlertMetrics.textBottom,
            ),
            child: only != null
                ? Text(
                    only,
                    textAlign: TextAlign.center,
                    style: _AlertMetrics.soloStyle(titleColor),
                    textHeightBehavior: _AlertMetrics.lines,
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Text(
                        title!,
                        style: _AlertMetrics.titleStyle(titleColor),
                        textHeightBehavior: _AlertMetrics.lines,
                      ),
                      SizedBox(
                        height: pop != null
                            ? _AlertMetrics.popoverTextGap
                            : _AlertMetrics.textGap,
                      ),
                      Text(
                        message!,
                        style: _AlertMetrics.messageStyle(
                          faded(
                            dark
                                ? _AlertMetrics.darkMessage
                                : _AlertMetrics.lightMessage,
                          ),
                        ),
                        textHeightBehavior: _AlertMetrics.lines,
                      ),
                    ],
                  ),
          );

    Widget capsule(int i) {
      final GlassAlertAction a = _ordered[i];
      final bool pressed = _highlighted == i;
      return Semantics(
        button: true,
        label: a.label,
        onTap: () => _dismiss(chosen: a),
        excludeSemantics: true,
        child: SizedBox(
          height: _AlertMetrics.actionHeight,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: faded(
                fill.withValues(
                  alpha: fill.a * (pressed ? _AlertMetrics.pressedFill : 1),
                ),
              ),
              borderRadius: BorderRadius.circular(
                _AlertMetrics.actionHeight / 2,
              ),
            ),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  a.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _AlertMetrics.labelStyle(
                    faded(a.destructive ? red : label),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    final Widget actions = LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final List<Widget> capsules = <Widget>[
          for (var i = 0; i < _ordered.length; i++) capsule(i),
        ];
        final Widget laid = _sideBySide
            ? Row(
                children: <Widget>[
                  Expanded(child: capsules[0]),
                  const SizedBox(width: _AlertMetrics.actionGap),
                  Expanded(child: capsules[1]),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  for (var i = 0; i < capsules.length; i++) ...<Widget>[
                    if (i > 0) const SizedBox(height: _AlertMetrics.actionGap),
                    capsules[i],
                  ],
                ],
              );
        final double height = _sideBySide
            ? _AlertMetrics.actionHeight
            : _ordered.length * _AlertMetrics.actionHeight +
                  (_ordered.length - 1) * _AlertMetrics.actionGap;
        final Size box = Size(constraints.maxWidth, height);
        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (PointerDownEvent e) => _actionsDown(e, box),
          onPointerMove: (PointerMoveEvent e) => _actionsMove(e, box),
          onPointerUp: (PointerUpEvent e) => _actionsUp(e, box),
          onPointerCancel: _actionsCancel,
          child: laid,
        );
      },
    );

    final List<GlassAlertTextField> textFields = widget.route.textFields;
    Widget field(int i) {
      final GlassAlertTextField f = textFields[i];
      final bool first = i == 0;
      final bool last = i == textFields.length - 1;
      return SizedBox(
        height: _AlertMetrics.actionHeight,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            DecoratedBox(
              decoration: BoxDecoration(
                color: faded(fill),
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(
                    first ? _AlertMetrics.actionHeight / 2 : 0,
                  ),
                  bottom: Radius.circular(
                    last ? _AlertMetrics.actionHeight / 2 : 0,
                  ),
                ),
              ),
            ),
            if (!last)
              Positioned(
                left: _AlertMetrics.fieldTextInset,
                right: _AlertMetrics.fieldTextInset,
                bottom: 0,
                height: 1,
                child: ColoredBox(
                  color: faded(
                    dark
                        ? _AlertMetrics.darkSeparator
                        : _AlertMetrics.lightSeparator,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: _AlertMetrics.fieldTextInset,
              ),
              child: Center(
                child: CupertinoTextField(
                  controller: _controllers[i],
                  autofocus: first,
                  obscureText: f.obscureText,
                  keyboardType: f.keyboardType,
                  placeholder: f.placeholder,
                  placeholderStyle: _AlertMetrics.fieldStyle(
                    faded(
                      dark
                          ? _AlertMetrics.darkPlaceholder
                          : _AlertMetrics.lightPlaceholder,
                    ),
                  ),
                  style: _AlertMetrics.fieldStyle(faded(label)),
                  cursorColor: _AlertMetrics.cursor,
                  cursorWidth: 2,
                  cursorHeight: 23,
                  cursorRadius: const Radius.circular(1),
                  padding: EdgeInsets.zero,
                  decoration: null,
                  contextMenuBuilder: GlassEditMenu.builder,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final Widget? fields = textFields.isEmpty
        ? null
        : Padding(
            padding: EdgeInsets.fromLTRB(
              _AlertMetrics.fieldInset,
              text == null ? _AlertMetrics.actionInset : _AlertMetrics.fieldTop,
              _AlertMetrics.fieldInset,
              _AlertMetrics.fieldBottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (var i = 0; i < textFields.length; i++) field(i),
              ],
            ),
          );

    // Taller than the screen allows, the text scrolls (UIKit's header);
    // the alert keeps to the space above the keyboard.
    final double bottom = math.max(
      padding.bottom,
      MediaQuery.viewInsetsOf(context).bottom,
    );
    final double room =
        screen.height - padding.top - bottom - 2 * _AlertMetrics.actionInset;
    final Widget alert = SizedBox(
      width: pop != null
          ? _PopoverMetrics.actionSheetWidth
          : math.min(_AlertMetrics.width, screen.width - 2 * 16),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: math.max(0, room)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (text != null)
              Flexible(child: SingleChildScrollView(child: text)),
            ?fields,
            Padding(
              padding: const EdgeInsets.all(_AlertMetrics.actionInset),
              child: actions,
            ),
          ],
        ),
      ),
    );

    if (pop != null) {
      // From a source: a popover by it, with no dim.
      return Stack(
        children: <Widget>[
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _cancel,
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              ignoring: _dismissing,
              child: _PopoverLayout(
                source: widget.route.source!,
                size: null,
                insets: padding.copyWith(bottom: bottom),
                arrow: _arrow,
                scale: math.max(0, pop.scale.value),
                travel: pop.travel.value,
                shadow: pop.shown,
                devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
                child: Semantics(
                  scopesRoute: true,
                  namesRoute: true,
                  explicitChildNodes: true,
                  label: title ?? message,
                  child: GlassPresence(
                    amount: _presence,
                    child: Glass._popover(
                      _arrow,
                      radius: _PopoverMetrics.radius,
                      child: alert,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.route.sheet ? _cancel : null,
            child: ColoredBox(color: Color.fromRGBO(0, 0, 0, dim)),
          ),
        ),
        // The alert's place: the middle of the safe area.
        Positioned.fill(
          top: padding.top,
          bottom: bottom,
          child: Center(
            child: IgnorePointer(
              ignoring: _dismissing,
              child: Transform.scale(
                scale: scale,
                child: Semantics(
                  scopesRoute: true,
                  namesRoute: true,
                  explicitChildNodes: true,
                  label: title ?? message,
                  child: GlassPresence(
                    amount: _presence,
                    child: Glass(
                      radius: _AlertMetrics.radius,
                      interactive: true,
                      child: alert,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
