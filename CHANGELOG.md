## Unreleased

* `Glass` is now UIKit's glass (`UIGlassEffect`), measured at 30 to 400pt:
  the tab bar's material at any size, with the inputs UIKit gives each size
  (refraction, frost, shadow, and for large glass its fixed appearance and
  bleed), Apple's continuous corners, a `clear` style, `tint` and
  `brightness`. Small glass turns light or dark with what is behind it.
* Breaking: `GlassMaterial` and `Glass.material` are gone; use
  `Glass(style: GlassStyle.regular or GlassStyle.clear)`.
* New: `GlassGroup`, UIKit's glass container (`UIGlassContainerEffect`).
  The `Glass` in it is drawn as one glass whose shapes melt together within
  its `spacing`, with UIKit's union (measured on iOS 26.5): a neck where
  they come within half the spacing, the inputs of its smallest and largest
  glass, one appearance for the group, tints that stay with their glass.
* New: `Glass.visible` materializes and dematerializes the glass as UIKit's
  does when its effect is set in an animation: blur, refraction, color, rim
  and shadow grow or fade together over half a second.

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

