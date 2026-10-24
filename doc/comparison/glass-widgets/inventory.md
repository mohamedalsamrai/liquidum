# UIKit's glass widgets: inventory and stage plan

Stage 0 of copying every UIKit component that uses Liquid Glass into
Liquidum. Surveyed on 2026-10-24 in the iOS 26.5 simulator (iPhone 17 Pro
Max, 440 × 956 pt): a temporary native catalog laid out each candidate over
colored blocks and dumped the window's layer tree at rest, 0.6 s into a
press, and after taps. Sizes are in points. Screenshots:
[`0-inventory.jpg`](0-inventory.jpg).

## Two kinds of glass

Everything that uses glass is built from one of two parts:

- **The glass material.** A glass group (`_GlassGroupView`) holding a
  backdrop layer with UIKit's `glassBackground` filter, clipped to one or
  more SDF shapes, with the content over it drawn through
  `vibrantColorMatrix`. The tab bar's platter is one.
- **The liquid lens** (`_UILiquidLensView`). At rest, a frosted pill faded in
  by `opacityPair`. Pressed or dragged, it lifts into clear glass: a backdrop,
  a displacement map, a blur, the glass group and `glassForeground`, with a
  `DestOutView` erasing what it covers. The tab bar's selection is one.

Pressing glass that responds to touch adds UIKit's flex interaction (the
swell and the fingertip glow, `_UIFlexInteractionGlowContainerView`), the
same one the tab bar's platter uses. Menus grow out of their source through
`_UIMagicMorphView`, the morph the tab bar's minimize crossfade uses.

## What uses which

| Component | Glass | Observed |
|---|---|---|
| `UITabBar` | material + lens | done: stages 1–6 and refinements |
| `UIGlassEffect` (`.regular`, `.clear`, `tintColor`) | material | any shape (capsule, rounded rect) |
| `UIGlassEffect.isInteractive` | material + flex | glow and swell when pressed; plain glass doesn't react |
| `UIGlassContainerEffect` | material, one group | shapes within `spacing` share one backdrop and melt together through a bridge |
| `UIButton` `.glass()`, `.prominentGlass()`, `.clearGlass()`, `.prominentClearGlass()` | material + flex | text capsule 38.3 high, icon circle 34.3; prominent is filled with the tint |
| `UISearchTextField` | material | at rest and focused |
| `UISwitch` | lens | 37 × 24 lens thumb on a 63 × 28 track; lifts while pressed |
| `UISlider` | lens | 37 × 24 lens thumb on a 6-point track; lifts while dragged |
| `UISegmentedControl` | lens | selection lens inset 2; lifts while dragged, not when another segment is tapped |
| `UINavigationBar` items | material, one group | 44-high platters: the back button a circle, grouped items a capsule; a press squeezes the platter (62 × 44 to 57 × 40) |
| `UIToolbar` items | material, one group | 48-high circles and capsules on one backdrop, the prominent item filled |
| Search in the toolbar position | material | a 384 × 48 field at the bottom |
| Pull-down menu (`showsMenuAsPrimaryAction`) | material + morph | the button's glass hides; a 250 × 104 platter grows from it |
| Context menu | material + morph | grows from the touch point |
| Back button's history menu | material + morph | long press on the back button |
| `UIDatePicker` (compact) overlay | material | 320 × 334 calendar platter, radius 28 |
| Sheet (`UISheetPresentationController`) | material | glass panel inset 8 from the screen's edges |
| `UIAlertController` alert and action sheet | material | 320 × 268 card, radius 34, 48-high capsule buttons; on iPhone without a source, the action sheet is the same card |
| Popover | material | glass with an arrow |

No glass in iOS 26.5, even pressed: `UIStepper`, `UIPageControl` (a plain
blur), `UIProgressView`, the plain system button, `UIColorWell`'s swatch.
Out of reach for an app: the keyboard, the color picker and the share sheet
run outside the app's process. Not seen yet: the edit menu (it needs actions
to show) and the navigation bar's scroll-edge effect (it needs a scroll
view); both are checked in their stages.

## Stage plan

Each stage is compared with UIKit at the same size, background and gesture,
frame by frame where it moves, before the next one starts. Numbers go in a
`metrics.txt` per stage, as for the tab bar.

1. **The glass material**: `UIGlassEffect` regular and clear, tinted, light
   and dark, any shape, content drawn vibrantly, and the interactive press.
   Liquidum's `Glass` is rebuilt on the tab bar's measured optics, so every
   surface shares one material (issue #2).
2. **Glass groups**: `UIGlassContainerEffect`, shapes melting together
   within a spacing, and shapes appearing and leaving. The bars' platters
   are built on it.
3. **Glass buttons**: the four `UIButton` glass styles, their sizes, labels,
   prominent fill, and press.
4. **Lens controls**: switch, slider and segmented control, on the tab bar's
   lens.
5. **Bars**: the navigation bar's platters, the toolbar, the bottom search
   field, presses, and the scroll-edge effect if there is one.
6. **Menus and morphs**: pull-down and context menus, the back button's
   menu, the date picker's overlay, the edit menu.
7. **Presentations**: sheets, alerts and action sheets, popovers.
