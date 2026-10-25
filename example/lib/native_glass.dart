import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// A piece of glass for the comparison: where it is, its shape and style.
@immutable
class GlassSpec {
  const GlassSpec(
    this.rect, {
    this.radius,
    this.clear = false,
    this.tint,
    this.interactive = false,
  });

  /// In the reference screen's points.
  final Rect rect;

  /// The corner radius; a capsule when null.
  final double? radius;

  /// UIKit's clear glass rather than its regular glass.
  final bool clear;

  final Color? tint;
  final bool interactive;
}

/// Shapes to compare, by name (the comparison's `glass=<name>` flag). The
/// same rectangles as the research catalog's pages.
const Map<String, List<GlassSpec>> glassSets = <String, List<GlassSpec>>{
  'sizes': <GlassSpec>[
    GlassSpec(Rect.fromLTWH(70, 70, 300, 30)),
    GlassSpec(Rect.fromLTWH(70, 120, 300, 44)),
    GlassSpec(Rect.fromLTWH(70, 184, 300, 62)),
    GlassSpec(Rect.fromLTWH(70, 266, 300, 100)),
    GlassSpec(Rect.fromLTWH(70, 386, 48, 48)),
    GlassSpec(Rect.fromLTWH(138, 386, 100, 100)),
    GlassSpec(Rect.fromLTWH(70, 506, 300, 120), radius: 12),
    GlassSpec(Rect.fromLTWH(70, 646, 300, 120), radius: 40),
    GlassSpec(Rect.fromLTWH(70, 786, 300, 62), clear: true),
  ],
  'clears': <GlassSpec>[
    GlassSpec(Rect.fromLTWH(70, 70, 300, 30), clear: true),
    GlassSpec(Rect.fromLTWH(70, 220, 300, 48), clear: true),
    GlassSpec(Rect.fromLTWH(70, 370, 300, 62), clear: true),
    GlassSpec(Rect.fromLTWH(70, 520, 300, 80), clear: true),
    GlassSpec(Rect.fromLTWH(70, 670, 300, 100), clear: true),
  ],
  'tints': <GlassSpec>[
    GlassSpec(Rect.fromLTWH(70, 70, 300, 62), tint: Color(0xFF0088FF)),
    GlassSpec(Rect.fromLTWH(70, 180, 300, 62), tint: Color(0xFFFF383C)),
    GlassSpec(Rect.fromLTWH(70, 290, 300, 62), tint: Color(0x800088FF)),
    GlassSpec(
      Rect.fromLTWH(70, 400, 300, 62),
      clear: true,
      tint: Color(0xFF0088FF),
    ),
    GlassSpec(Rect.fromLTWH(70, 510, 300, 62), interactive: true),
    GlassSpec(Rect.fromLTWH(70, 620, 300, 62)),
  ],
  'heights': <GlassSpec>[
    GlassSpec(Rect.fromLTWH(70, 70, 300, 56)),
    GlassSpec(Rect.fromLTWH(70, 146, 300, 62)),
    GlassSpec(Rect.fromLTWH(70, 228, 300, 64)),
    GlassSpec(Rect.fromLTWH(70, 312, 300, 66)),
    GlassSpec(Rect.fromLTWH(70, 398, 300, 70)),
    GlassSpec(Rect.fromLTWH(70, 488, 300, 80)),
    GlassSpec(Rect.fromLTWH(70, 588, 300, 90)),
    GlassSpec(Rect.fromLTWH(70, 698, 300, 160), radius: 30),
  ],
  // Apart, for the shadows below them.
  'apart': <GlassSpec>[
    GlassSpec(Rect.fromLTWH(70, 80, 300, 30)),
    GlassSpec(Rect.fromLTWH(70, 190, 300, 62)),
    GlassSpec(Rect.fromLTWH(70, 330, 300, 100)),
    GlassSpec(Rect.fromLTWH(70, 510, 300, 120), radius: 24),
    GlassSpec(Rect.fromLTWH(70, 720, 48, 48)),
    GlassSpec(Rect.fromLTWH(200, 700, 160, 160)),
  ],
  // Panels, as sheets and alerts are.
  'big': <GlassSpec>[
    GlassSpec(Rect.fromLTWH(40, 40, 360, 200), radius: 30),
    GlassSpec(Rect.fromLTWH(40, 270, 360, 250), radius: 34),
    GlassSpec(Rect.fromLTWH(40, 550, 360, 300), radius: 40),
  ],
  'big2': <GlassSpec>[
    GlassSpec(Rect.fromLTWH(20, 60, 400, 400), radius: 34),
    GlassSpec(Rect.fromLTWH(70, 500, 300, 120)),
    GlassSpec(Rect.fromLTWH(70, 660, 300, 160)),
  ],
  'bar': <GlassSpec>[GlassSpec(Rect.fromLTWH(21, 873, 398, 62))],
};

/// Apple's glass (`UIGlassEffect`), as a platform view: [shapes] over
/// whatever Flutter paints behind it. iOS 26 only.
class NativeGlass extends StatelessWidget {
  const NativeGlass({super.key, required this.shapes});

  final List<GlassSpec> shapes;

  static bool get isAvailable =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  @override
  Widget build(BuildContext context) {
    return UiKitView(
      viewType: 'liquidum/native_glass',
      creationParams: <String, Object>{
        'shapes': <Map<String, Object>>[
          for (final GlassSpec s in shapes)
            <String, Object>{
              'x': s.rect.left,
              'y': s.rect.top,
              'width': s.rect.width,
              'height': s.rect.height,
              'radius': ?s.radius,
              'style': s.clear ? 'clear' : 'regular',
              if (s.tint case final Color tint) 'tint': tint.toARGB32(),
              'interactive': s.interactive,
            },
        ],
      },
      creationParamsCodec: const StandardMessageCodec(),
    );
  }
}
