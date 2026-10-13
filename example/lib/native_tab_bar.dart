import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'tabs.dart';

/// Apple's own iOS tab bar (`UITabBarController`), embedded as a platform view
/// for comparison with Liquidum's `GlassTabBar`. Place it flush with the bottom of the
/// screen; the native bar floats in its own position within it.
class NativeTabBar extends StatefulWidget {
  const NativeTabBar({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
  });

  /// Room for the bar, its bottom margin, and the lens rising above it.
  static const double height = 110;

  /// Whether Apple's bar exists here: only on iOS.
  static bool get isAvailable =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  final List<TabSpec> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  State<NativeTabBar> createState() => _NativeTabBarState();
}

class _NativeTabBarState extends State<NativeTabBar> {
  MethodChannel? _channel;

  void _created(int id) {
    _channel = MethodChannel('liquidum/native_tab_bar/$id')
      ..setMethodCallHandler((MethodCall call) async {
        if (call.method == 'selected') {
          widget.onSelected(call.arguments as int);
        }
      });
  }

  @override
  void didUpdateWidget(NativeTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex != widget.selectedIndex) {
      _channel?.invokeMethod<void>('select', widget.selectedIndex);
    }
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return UiKitView(
      viewType: 'liquidum/native_tab_bar',
      creationParams: <String, Object>{
        'selected': widget.selectedIndex,
        'items': <Map<String, String>>[
          for (final TabSpec item in widget.items)
            <String, String>{'label': item.label, 'symbol': item.symbol},
        ],
      },
      creationParamsCodec: const StandardMessageCodec(),
      // Let the native bar have every touch at once, so its press-and-drag
      // lens responds exactly as it does in a native app.
      gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
        Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new),
      },
      onPlatformViewCreated: _created,
    );
  }
}
