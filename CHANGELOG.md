## Unreleased

* `Glass` is now UIKit's glass (`UIGlassEffect`), measured at 30 to 400pt:
  the tab bar's material at any size, with the inputs UIKit gives each size
  (refraction, frost, shadow, and for large glass its fixed appearance and
  bleed), Apple's continuous corners, a `clear` style, `tint` and
  `brightness`. Small glass turns light or dark with what is behind it.
* Breaking: `GlassMaterial` and `Glass.material` are gone; use
  `Glass(style: GlassStyle.regular or GlassStyle.clear)`.

## 0.2.2

* License: Liquidum is now under the MIT License, free for any use,
  commercial included.
* Breaking: the `debug*` parameters of `GlassTabBar` are replaced by a
  `GlassTabBarDebug` widget above the bar, whose `GlassTabBarDebugOptions`
  hold the same settings. `GlassTabBarPhysics`, `GlassAppearance`,
  `GlassTabBarDebugView` and `GlassTabBarOptics` moved to
  `package:liquidum/liquidum_debug.dart`, which is not covered by semantic
  versioning. `GlassSpring`, `GlassShape`, `GlassField`,
  `GlassBackdropState`, `GlassBackdrop.under` and the render objects
  (`RenderGlass`, `RenderGlassTabBar`) are no longer public.
* Backdrop sampling follows drawn frames: no timers or snapshots while idle
  or in the background. Over a still backdrop the bar now stops reading it;
  before, each reading drew frames that called for the next one, up to 20
  readings a second for as long as the bar was shown.

