## 0.2.0

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

## 0.1.1

* License: the Licensed Work now covers version 0.0.1 and later, each
  version changes to the Apache License 2.0 four years after it is
  published, and the non-commercial definition is clearer (indirect
  revenue, freelance and client work). Code and behavior are unchanged.
* README: clearer description, a license summary at the top, and a note
  that Liquidum is not affiliated with Apple.
* Source comments reworded; research notes moved to `doc/comparison`.

## 0.1.0

* `GlassTab.search`: a search tab in its own glass circle, as UIKit's
  `UISearchTab`; with a `controller`, it opens into a search field (the tabs
  collapse into a circle, a close button while typing, the bar above the
  keyboard).
* `accessory`: UIKit's bottom accessory, a glass capsule above the bar.
* `minimizeOnScroll`: the bar collapses as a page scrolls down, with UIKit's
  springs (`tabBarMinimizeBehavior`), its tabs blurring and fading in place
  and the selected icon sliding into the circle, as UIKit's crossfade does.
* Accessibility: Increase Contrast and Reduce Motion followed from the
  system; `reduceTransparency` to draw the glass as Reduce Transparency does.
* The frost is now a real blur drawn before the glass, as UIKit's: no more
  ghosting behind fine lines, and closer to UIKit at the bar's edges. It
  takes a second backdrop capture.
* The lens's darker band inside its top edge, as UIKit's.
* Filtered sampling of the backdrop and the tabs' content.

## 0.0.1

First preview.

* `GlassTabScaffold` and `GlassTab`: an iOS 26 tab bar with each tab's page,
  its own navigator and kept state, in a few lines.
* `GlassTabBar`: the bar alone, with UIKit's glass optics, the lifting lens
  and its springs, lighting, and light and dark appearances that adapt to the
  content under it.
* Styling: selected and unselected colors, badges, selected icons, SVG and
  image icons, label style, glass tints for the bar, the resting selection
  and the lens (`GlassDecoration` with gradients, drop shadows, inner
  shadows, and tinted or painted fills), padding and margin.
* Right-to-left layout, and UIKit's bar widths for three tabs or fewer.
* `Glass`, `GlassMaterial` and `GlassBackdrop`: liquid glass for any widget.
