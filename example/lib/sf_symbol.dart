import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// An SF Symbol drawn by UIKit in the configuration iOS 26 tab bars use, and
/// tinted by Flutter. Place it centered: like UIKit, it centers its alignment
/// rect there. Shows [fallback] where UIKit is not available.
class SfSymbol extends StatelessWidget {
  const SfSymbol(this.name, {super.key, required this.fallback, this.color});

  final String name;
  final IconData fallback;

  /// Defaults to the ambient [IconTheme]'s color.
  final Color? color;

  static const _channel = MethodChannel('liquidum/sf_symbols');

  // Read from UITabBar's item image views on iOS 26.
  static const _tabBarConfiguration = <String, Object>{
    'pointSize': 18.0,
    'weight': 'medium',
    'scale': 'large',
  };

  static final Map<String, Future<_Rendered?>> _cache =
      <String, Future<_Rendered?>>{};

  static Future<_Rendered?> _load(String name) {
    return _cache[name] ??= _channel
        .invokeMapMethod<String, Object?>('render', <String, Object>{
          'name': name,
          ..._tabBarConfiguration,
        })
        .then((Map<String, Object?>? m) {
          if (m == null) {
            return null;
          }
          final List<double> i = (m['insets']! as List<Object?>).cast<double>();
          return _Rendered(
            m['png']! as Uint8List,
            Size(m['width']! as double, m['height']! as double),
            // Moves the drawing so its alignment rect, not its drawing
            // bounds, is centered where the symbol is placed.
            Offset((i[2] - i[0]) / 2, (i[3] - i[1]) / 2),
          );
        })
        .catchError((Object _) => null);
  }

  /// Renders [names] ahead of time, so they show on the first frame.
  static Future<void> precache(Iterable<String> names) =>
      Future.wait(names.map(_load));

  @override
  Widget build(BuildContext context) {
    final Color color = this.color ?? IconTheme.of(context).color!;
    return FutureBuilder<_Rendered?>(
      future: _load(name),
      builder: (BuildContext context, AsyncSnapshot<_Rendered?> snapshot) {
        final _Rendered? symbol = snapshot.data;
        if (symbol == null) {
          return snapshot.connectionState == ConnectionState.done
              ? Icon(fallback, size: 26, color: color)
              : const SizedBox.shrink();
        }
        return Transform.translate(
          offset: symbol.alignment,
          child: Image.memory(
            symbol.png,
            width: symbol.size.width,
            height: symbol.size.height,
            color: color,
            colorBlendMode: BlendMode.srcIn,
            gaplessPlayback: true,
          ),
        );
      },
    );
  }
}

class _Rendered {
  const _Rendered(this.png, this.size, this.alignment);

  final Uint8List png;
  final Size size;
  final Offset alignment;
}
