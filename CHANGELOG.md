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
