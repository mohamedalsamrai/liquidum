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
    this.group,
    this.spacing = 0,
    this.appear = false,
  });

  /// In the reference screen's points.
  final Rect rect;

  /// The corner radius; a capsule when null.
  final double? radius;

  /// UIKit's clear glass rather than its regular glass.
  final bool clear;

  final Color? tint;
  final bool interactive;

  /// The glass group it is in (`UIGlassContainerEffect`, [GlassGroup]), if
  /// any: specs with the same number are one group, whose spacing is its
  /// first spec's [spacing].
  final int? group;
  final double spacing;

  /// Whether it materializes and dematerializes at the comparison's
  /// `appear=` times (hidden until then).
  final bool appear;
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
  // Rounded rectangles up to 64pt and above (UIKit's large glass).
  'corners': <GlassSpec>[
    GlassSpec(Rect.fromLTWH(40, 70, 60, 60), radius: 16),
    GlassSpec(Rect.fromLTWH(140, 70, 60, 60), radius: 8),
    GlassSpec(Rect.fromLTWH(240, 70, 44, 44), radius: 12),
    GlassSpec(Rect.fromLTWH(330, 70, 64, 64), radius: 24),
    GlassSpec(Rect.fromLTWH(40, 180, 160, 60), radius: 16),
    GlassSpec(Rect.fromLTWH(240, 180, 160, 50), radius: 10),
    GlassSpec(Rect.fromLTWH(40, 290, 100, 100), radius: 16),
    GlassSpec(Rect.fromLTWH(180, 290, 100, 100), radius: 30),
    GlassSpec(Rect.fromLTWH(40, 440, 360, 120), radius: 24),
    GlassSpec(Rect.fromLTWH(40, 610, 80, 80), radius: 20),
    GlassSpec(Rect.fromLTWH(160, 610, 240, 80), radius: 12),
    GlassSpec(Rect.fromLTWH(40, 730, 60, 60), radius: 16, clear: true),
    GlassSpec(Rect.fromLTWH(140, 730, 160, 60), radius: 16, clear: true),
    GlassSpec(Rect.fromLTWH(320, 730, 80, 80), radius: 20, clear: true),
  ],
  'bar': <GlassSpec>[GlassSpec(Rect.fromLTWH(21, 873, 398, 62))],
  // Glass groups, spacing 20 (as the catalog's groups page).
  'groups': <GlassSpec>[
    // Two capsules 0, 6 and 12 apart: joined, joined, apart but leaning.
    GlassSpec(Rect.fromLTWH(70, 60, 150, 62), group: 0, spacing: 20),
    GlassSpec(Rect.fromLTWH(220, 60, 150, 62), group: 0),
    GlassSpec(Rect.fromLTWH(67, 160, 150, 62), group: 1, spacing: 20),
    GlassSpec(Rect.fromLTWH(223, 160, 150, 62), group: 1),
    GlassSpec(Rect.fromLTWH(64, 260, 150, 62), group: 2, spacing: 20),
    GlassSpec(Rect.fromLTWH(226, 260, 150, 62), group: 2),
    // Three circles 4 apart.
    GlassSpec(Rect.fromLTWH(140, 370, 48, 48), group: 3, spacing: 20),
    GlassSpec(Rect.fromLTWH(192, 370, 48, 48), group: 3),
    GlassSpec(Rect.fromLTWH(244, 370, 48, 48), group: 3),
    // Capsules stacked 6 apart, flat sides facing; mixed heights 8 apart.
    GlassSpec(Rect.fromLTWH(30, 460, 160, 50), group: 4, spacing: 20),
    GlassSpec(Rect.fromLTWH(30, 516, 160, 50), group: 4),
    GlassSpec(Rect.fromLTWH(220, 470, 90, 44), group: 5, spacing: 20),
    GlassSpec(Rect.fromLTWH(318, 442, 100, 100), group: 5),
    // A 2x2 grid of rounded squares 8 apart.
    GlassSpec(
      Rect.fromLTWH(140, 620, 76, 76),
      radius: 20,
      group: 6,
      spacing: 20,
    ),
    GlassSpec(Rect.fromLTWH(224, 620, 76, 76), radius: 20, group: 6),
    GlassSpec(Rect.fromLTWH(140, 704, 76, 76), radius: 20, group: 6),
    GlassSpec(Rect.fromLTWH(224, 704, 76, 76), radius: 20, group: 6),
  ],
  // Glass appearing and leaving (the `appear=` flag): beside glass in a
  // group, and alone (as the catalog's appear page).
  'appear': <GlassSpec>[
    GlassSpec(Rect.fromLTWH(60, 180, 150, 62), group: 0, spacing: 20),
    GlassSpec(Rect.fromLTWH(218, 180, 150, 62), group: 0, appear: true),
    GlassSpec(Rect.fromLTWH(145, 520, 150, 62), appear: true),
  ],
  // Styles and tints in groups, spacing 20.
  'groupstyles': <GlassSpec>[
    // Plain and blue, 6 apart: the tint reaches into the neck.
    GlassSpec(Rect.fromLTWH(40, 80, 160, 62), group: 0, spacing: 20),
    GlassSpec(
      Rect.fromLTWH(206, 80, 160, 62),
      tint: Color(0xFF0088FF),
      group: 0,
    ),
    // Two clear, 6 apart.
    GlassSpec(
      Rect.fromLTWH(40, 220, 160, 62),
      clear: true,
      group: 1,
      spacing: 20,
    ),
    GlassSpec(Rect.fromLTWH(206, 220, 160, 62), clear: true, group: 1),
    // Regular and clear, 6 apart: drawn apart, no neck.
    GlassSpec(Rect.fromLTWH(40, 360, 160, 62), group: 2, spacing: 20),
    GlassSpec(Rect.fromLTWH(206, 360, 160, 62), clear: true, group: 2),
    // A large panel with a small capsule 8 above it.
    GlassSpec(Rect.fromLTWH(140, 500, 160, 44), group: 3, spacing: 20),
    GlassSpec(Rect.fromLTWH(40, 552, 360, 200), radius: 34, group: 3),
  ],
};

/// Apple's glass (`UIGlassEffect`), as a platform view: [shapes] over
/// whatever Flutter paints behind it. iOS 26 only.
class NativeGlass extends StatelessWidget {
  const NativeGlass({
    super.key,
    required this.shapes,
    this.appearAt,
    this.leaveAt,
    this.speed = 1,
  });

  final List<GlassSpec> shapes;

  /// When the appearing shapes materialize and dematerialize (seconds after
  /// the view is made), in a half-second animation.
  final double? appearAt;
  final double? leaveAt;

  /// The view's layer speed (below 1 slows its animations).
  final double speed;

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
              'group': ?s.group,
              'spacing': s.spacing,
              'appear': s.appear,
            },
        ],
        'appearAt': ?appearAt,
        'leaveAt': ?leaveAt,
        'speed': speed,
      },
      creationParamsCodec: const StandardMessageCodec(),
    );
  }
}
