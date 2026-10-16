/// Measurement and debugging hooks for Liquidum's comparison harness: the
/// tab bar's debug views and optical stages, its physics and its adaptive
/// appearance, with the hooks that log them.
///
/// This library is not covered by semantic versioning. Anything in it may
/// change or go away in any release. Apps use `package:liquidum/liquidum.dart`.
library;

export 'src/tab_bar/appearance.dart' show GlassAppearance;
export 'src/tab_bar/debug.dart'
    show
        GlassTabBarDebug,
        GlassTabBarDebugOptions,
        GlassTabBarDebugView,
        GlassTabBarOptics;
export 'src/tab_bar/physics.dart' show GlassTabBarPhysics;
