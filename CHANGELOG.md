## Unreleased

* `Glass` is now UIKit's glass (`UIGlassEffect`), measured at 30 to 400pt:
  the tab bar's material at any size, with the inputs UIKit gives each size
  (refraction, frost, shadow, and for large glass its fixed appearance and
  bleed), Apple's continuous corners, UIKit's refraction around them (it
  turns well before a side meets its corner, and in large regular glass
  leans toward the center), a `clear` style, `tint` and `brightness`.
  Small glass turns light or dark with what is behind it.
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
* New: `GlassButton`, UIKit's glass buttons (`UIButton.Configuration`'s
  `glass()`, `prominentGlass()`, `clearGlass()` and
  `prominentClearGlass()`): a label, an icon or both, four sizes, UIKit's
  metrics, and its vibrant label, which takes the colors of the glass
  under it.
* New: `Glass.interactive`, UIKit's interactive glass
  (`UIGlassEffect.isInteractive`): pressed, the glass swells by UIKit's
  points for its size, lightens and glows under the finger, stretches
  toward a drag and springs back, on UIKit's springs.
* New: `GlassSwitch`, `GlassSlider` and `GlassSegmentedControl`, UIKit's
  iOS 26 controls whose thumb or selection is the tab bar's liquid lens:
  a 63 x 28 switch, a 34pt slider, a 32pt segmented control, with UIKit's
  measured geometry, colors, springs and lens for each (the switch's and
  slider's thumbs lift into UIKit's small lens, the selection into the
  bar's), compared with UIKit at rest and in motion.
* New: `GlassPage` and `GlassBarItem`, UIKit's iOS 26 bars over a page: a
  navigation bar of glass (a title, a back button, leading and trailing
  items, a large title that collapses into the bar) and a toolbar or a
  search field at the bottom, with UIKit's metrics, grouping, presses and
  its scroll-edge effect where content scrolls under them, light and dark.
* New: `GlassButton.menu` and `GlassMenuItem`, UIKit's pull-down menus
  (`showsMenuAsPrimaryAction`): a touch opens a 250pt platter of large
  glass that grows out of the button with UIKit's liquid morph (the button
  and the menu melt as two shapes on UIKit's springs, fitted to its frames
  on iOS 26.5) and morphs back into it. UIKit's rows, checkmarks, icons,
  dividers, destructive items and placement (down, or up with the rows
  reversed near the bottom; from the right edge near the screen's right),
  a finger that slides from the button onto a row and lifts, and
  submenus (`GlassMenuItem.submenu`) that open over the menu. `onPressed`
  is now optional on a button with a menu.
* New: `GlassBarItem.menu`: a bar item opens its menu out of its glass, as
  UIKit's (`onPressed` is now optional on an item with a menu). Holding a
  `GlassPage`'s back button for 0.6s opens UIKit's history menu: the titles
  of the pages under it in its navigator, nearest first; lifting the
  finger on one goes back to it.
* New: `GlassContextMenu(items:, child:)`, UIKit's context menus
  (`UIContextMenuInteraction`), measured on iOS 26.5: a resting finger
  grows the view; after 0.8s it lifts over the dimmed screen with its
  shadow and the menu grows out of its center with the liquid morph, 20pt
  beside it on the side with more room. Slide onto a row and lift to
  choose it; a tap outside closes the menu. A shorter touch stays the
  view's own.
* New: `GlassPage`'s bars between two pages, as UIKit's push and pop: the
  bars stay while the pages slide under them; a platter whose items change
  morphs into the other page's, swelling and settling as its items
  crossfade; one on a single page melts into its neighbor or grows out of
  it; the back button and a toolbar on one page only materialize or go;
  titles ride with their pages. A swipe back drives it. Nothing to set.
* New: `GlassEditMenu`, UIKit's edit menu (`UIEditMenuInteraction`) on
  iOS 26.5: the row of actions on a capsule of glass, 15pt below the
  selection (above it without room), growing out of it and shrinking back
  on UIKit's springs; actions that do not fit give way to a chevron that
  melts the capsule into the full menu, Cut, Copy and Paste as tiles
  across its top. For a text field,
  `contextMenuBuilder: GlassEditMenu.builder`; your own actions with
  `GlassEditMenu(anchors:, items:)`.
* Fix: menu rows with icons but no checkmark start their icon and label
  where UIKit's do (40 and 64pt; 55 and 79 only beside a checkmark).
* Fix: a tinted `Glass` kept its tint while dematerializing
  (`visible: false`); the tint now comes and goes with the glass.
* Fix: hiding glass inside a hidden menu source (a back button with a
  history) now hides it too.
* Fix: a `GlassButton` with a menu inside a `GlassGroup` kept its glass
  while its menu was open; and it no longer adds a layer around its glass.
* Fix: glass in a `GlassGroup` drew its content (a `GlassButton`'s label)
  in the system's look instead of the group's when the group turned light
  or dark with what is behind it.
* Fix: on Android (Impeller's OpenGL ES backend) every glass drew what is
  behind it, and the tab bar its icons and labels, upside down: Flutter
  3.47 no longer stores those textures flipped. Liquidum now needs
  Flutter 3.47 or later.
* Faster: every glass read what is behind it with its own snapshot of the
  page; now one snapshot per drawn frame serves them all (a page of a dozen
  glass buttons and controls took about four times as many while it
  animated).
* Faster: the glass beside a `GlassBackdrop` (over it, in the same `Stack`,
  not inside it) reads the screen twice in all instead of twice each: the
  backdrop draws the frost of all of it right after its content, and then
  each glass is drawn from one read of that. A glass button's label, and a
  bar item's, is drawn in its glass's pass instead of reading the screen
  again. Flinging a page of a dozen glass buttons and controls on Android
  now misses 2% of frames instead of a third (two thirds before any of
  this); on iOS the buttons and bars draw as before, to the level.
* Fix: glass over a backdrop with no background of its own (see-through
  content) took it for black and turned dark.

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

