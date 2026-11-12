part of 'glass.dart';

/// Shows [items] in a glass menu when [child] is long-pressed, as UIKit's
/// context menus (`UIContextMenuInteraction`) on iOS 26.
///
/// ```dart
/// GlassContextMenu(
///   items: [
///     GlassMenuItem(label: 'Copy', icon: CupertinoIcons.doc_on_doc,
///         onPressed: copy),
///     GlassMenuItem(label: 'Share', icon: CupertinoIcons.share,
///         onPressed: share),
///     GlassMenuItem.divider(),
///     GlassMenuItem(label: 'Delete', icon: CupertinoIcons.trash,
///         destructive: true, onPressed: delete),
///   ],
///   child: photoCard,
/// )
/// ```
///
/// While a finger rests on [child], it slowly grows; after 0.8s it lifts
/// over the dimmed screen with a soft shadow and the menu grows out of it,
/// beside it on the side with more room. The finger can then slide onto a
/// row and lift to choose it; lifting it anywhere else leaves the menu
/// open. A tap outside the menu closes it, and [child] settles back into
/// its place. A shorter touch is [child]'s own: its taps work as before.
///
/// The lifted [child] is drawn again above the screen, with continuous
/// corners of 13pt (at its own size, growing as it lifts); its shadow
/// follows its opaque pixels.
class GlassContextMenu extends StatefulWidget {
  const GlassContextMenu({super.key, required this.items, required this.child});

  /// The menu's rows (see [GlassMenuItem]). With none, [child] has no menu.
  final List<GlassMenuItem> items;

  final Widget child;

  @override
  State<GlassContextMenu> createState() => _GlassContextMenuState();
}

class _GlassContextMenuState extends State<GlassContextMenu> {
  GlobalKey<_GlassMenuOverlayState>? _menu;
  Timer? _timer;
  int? _pointer;
  Offset _downAt = Offset.zero;
  bool _opened = false;

  Offset _toOverlay(Offset global) {
    final RenderObject? box = _menu?.currentContext?.findRenderObject();
    return box is RenderBox ? box.globalToLocal(global) : global;
  }

  // Puts the view in the overlay: growing under a resting finger
  // ([pressing]), or opened at once.
  void _show({required bool pressing}) {
    if (_menu != null || !mounted || widget.items.isEmpty) {
      return;
    }
    setState(() {
      _menu = _showGlassMenu(
        context: context,
        items: widget.items,
        sourceContent: const SizedBox.shrink(),
        preview: widget.child,
        pressing: pressing,
        onClosed: () {
          if (mounted) {
            setState(() {
              _menu = null;
              _opened = false;
            });
          }
        },
      );
    });
  }

  void _down(PointerDownEvent event) {
    if (_pointer != null || _menu != null || widget.items.isEmpty) {
      return;
    }
    _pointer = event.pointer;
    _downAt = event.position;
    _timer = Timer(_ContextMetrics.pressDelay, () {
      _timer = null;
      _show(pressing: true);
    });
  }

  void _move(PointerMoveEvent event) {
    if (event.pointer == _pointer &&
        !_opened &&
        (event.position - _downAt).distance > kTouchSlop) {
      _rest();
    }
  }

  void _lift(PointerEvent event) {
    if (event.pointer == _pointer) {
      _pointer = null;
      if (!_opened) {
        _rest();
      }
    }
  }

  // The finger left before the menu opened: the view shrinks back.
  void _rest() {
    _timer?.cancel();
    _timer = null;
    _later((_GlassMenuOverlayState menu) => menu.cancelPress());
  }

  // Runs [action] on the overlay now, or once it has built (it was put in
  // the overlay this frame).
  void _later(void Function(_GlassMenuOverlayState menu) action) {
    final GlobalKey<_GlassMenuOverlayState>? key = _menu;
    final _GlassMenuOverlayState? menu = key?.currentState;
    if (menu != null) {
      action(menu);
    } else if (key != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final _GlassMenuOverlayState? built = key.currentState;
        if (built != null) {
          action(built);
        }
      });
    }
  }

  void _longPressed(LongPressStartDetails details) {
    _opened = true;
    if (_menu != null) {
      _later((_GlassMenuOverlayState menu) => menu.open());
    } else {
      _timer?.cancel();
      _timer = null;
      _show(pressing: false);
    }
    HapticFeedback.mediumImpact();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool shown = _menu != null;
    Widget child = _GlassHiddenScope(
      hidden: shown || _GlassHiddenScope.above(context),
      child: _Hidden(hidden: shown, child: widget.child),
    );
    if (widget.items.isEmpty) {
      return child;
    }
    // The resting finger grows the view; the long press (which wins over
    // the child's own gestures only once it fires) opens the menu, and its
    // moves and lift go to the menu.
    child = Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: _lift,
      onPointerCancel: _lift,
      child: RawGestureDetector(
        behavior: HitTestBehavior.translucent,
        gestures: <Type, GestureRecognizerFactory>{
          LongPressGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
                () => LongPressGestureRecognizer(
                  duration: _ContextMetrics.openDelay,
                ),
                (LongPressGestureRecognizer r) {
                  r
                    ..onLongPressStart = _longPressed
                    ..onLongPressMoveUpdate = (LongPressMoveUpdateDetails d) {
                      _menu?.currentState?.track(_toOverlay(d.globalPosition));
                    }
                    ..onLongPressEnd = (LongPressEndDetails d) {
                      _menu?.currentState?.release(
                        _toOverlay(d.globalPosition),
                      );
                    };
                },
              ),
        },
        child: child,
      ),
    );
    return Semantics(
      onLongPress: () {
        _opened = true;
        _show(pressing: false);
      },
      onLongPressHint: 'Show menu',
      child: child,
    );
  }
}
