# liquidum

Liquid glass as a material for Flutter. This is a reconstruction of the iOS 26
look, not Apple's renderer. Its parameters are fitted to native iOS 26 glass,
which was measured in the iOS 26.5 simulator against ramp, stripe and color
backgrounds.

## Tab bar

An iOS 26 tab bar, with each tab's page, in one widget:

```dart
import 'package:flutter/cupertino.dart';
import 'package:liquidum/liquidum.dart';

void main() => runApp(
  const CupertinoApp(
    home: GlassTabScaffold(
      tabs: [
        GlassTab(icon: CupertinoIcons.house_fill, label: 'Home', page: HomePage()),
        GlassTab(icon: CupertinoIcons.search, label: 'Search', page: SearchPage()),
        GlassTab(icon: CupertinoIcons.bell_fill, label: 'Alerts', badge: '3', page: AlertsPage()),
      ],
    ),
  ),
);
```

The scaffold handles the rest the way an iOS app does:

- The bar floats over the pages, and its glass adapts to what is under it.
  With up to three tabs it is only as wide as they need and centered; with
  more it spans the screen, as in UIKit.
- Each tab keeps its page and that page's state.
- Each tab has its own navigator, so `Navigator.push` stays inside the tab.
- Tapping the selected tab again returns to its first page.
- The pages' bottom padding includes the bar.
- In right-to-left apps, the first tab is on the right.

Everything else is optional:

| | |
|---|---|
| `GlassTab(selectedIcon: …)` | the icon while the tab is selected |
| `GlassTab(badge: '3')` | a badge on the icon |
| `GlassTab(color: …)` | this tab's selected color |
| `GlassTab.custom(icon: anyWidget)` | an image or SVG icon; `tintIcon: false` keeps its own colors |
| `selectedColor` | the selected tab's color (UIKit's `tintColor`); default system blue |
| `unselectedColor` | the other tabs' color; by default they take UIKit's colors from the glass |
| `badgeColor` | default system red |
| `glassColor` | tints the bar's glass |
| `indicatorColor` | tints the glass under the selected tab at rest |
| `lensColor` | tints the lens while the bar is pressed or dragged |
| `glass`, `indicator`, `lens` | the same three, decorated like a `BoxDecoration`: `GlassDecoration(color:, gradient: LinearGradient(…), shadows: […], innerShadows: […])`; `fill: GlassFill.paint` paints the color as it is over the blur (as a design tool does) instead of tinting the glass the iOS way |
| `brightness`, `adaptive` | force light or dark; whether the bar adapts to the pages |
| `labelStyle` | for example a font family |
| `initialIndex`, `onTabChanged`, `controller` | the selected tab; switch from a page with `GlassTabScaffold.of(context).index = 1` |

Glass tints follow iOS's own tinted glass (`UIGlassEffect.tintColor`). The
tint is deeper where the glass is darker and true where it is white, and its
alpha sets how strongly it shows. UIKit's tab bar itself can't be tinted.

Colors, badges and the selected tint match UIKit's. They were measured in the iOS
26.5 simulator over white, gray and black. UIKit's iOS 26 bar has no unselected color
(it ignores `unselectedItemTintColor`), so `unselectedColor` goes beyond UIKit.
`GlassTabBar` is the bar alone, for apps that manage their own pages or
router.

## Building blocks

- **`GlassMaterial`**: what the glass is. Presets: `regular` and `regularDark`
  (bars and controls), `clear` and `clearDark` (lens-like), and `identity` (no
  effect, used to animate glass in and out). Materials can be animated with
  `GlassMaterial.lerp`.
- **`Glass`**: a rounded-rectangle or capsule surface made of a material, with
  a child drawn on top.
- **`GlassBackdrop`** and **`GlassBrightness`**: adaptive appearance. Wrap the
  content that glass floats over in a `GlassBackdrop`. A `GlassBrightness`
  under a surface then measures that content and switches between light and
  dark glass the way iOS bars do. It follows the system appearance, except
  over nearly black content (light glass turns dark) or nearly white content
  (dark glass turns light). `GlassTabBar` reads the content under it the same
  way and adapts as UIKit's tab bar does: its glass, symbols and labels take
  their colors from that content, and it switches between its light and dark
  appearances at UIKit's thresholds. Without a `GlassBackdrop` under it, it
  follows the system appearance.
- **`shaders/glass.frag`**: one backdrop pass. It computes:
  - the shape from an SDF;
  - inward refraction that is strongest at the rim, where it folds into a
    mirrored image;
  - a lengthwise lens for elongated shapes;
  - zoom and per-channel dispersion;
  - the frost veil;
  - the rim light;
  - an analytic soft shadow.

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Glass.precache();
  runApp(const App());
}

Glass(
  material: GlassMaterial.regular,
  child: SizedBox(width: 398, height: 62, child: tabs),
)
```

`example/lib/main.dart` is the scaffold above with four tabs. Press and slide to
move the clear lens between tabs, then release to select the tab under it. Judge
motion in profile or release mode, because debug builds are much slower on
device.

`example/lib/playground.dart` (run it with `flutter run -t lib/playground.dart`)
changes the bar's colors and appearance live. The switch at the top swaps in Apple's own tab bar
(`UITabBarController`, embedded as a platform view) in the same place over the
same content, so the two can be compared directly, including the pressed lens.
The example draws its tab symbols with UIKit, in the configuration read from
the native bar, so both bars use identical glyphs.

## Requirements and current limits

- Needs Impeller (`ImageFilter.shader`). Other backends get a plain frost.
- Glass reads what is painted before it, so paint it after its content (for
  example, later in a `Stack`). Glass painted later sees glass painted earlier.
- The surface must paint into the root layer: no ancestor `Opacity`,
  `ShaderMask` or similar save layer.
- Geometry is refreshed when the surface paints, so keep it out of subtrees
  that move without repainting it (for example, items in a scrolling list).
- The tab bar draws its tabs from an image of them, which it renders again
  whenever they repaint. An icon that contains a `RepaintBoundary` hides its
  repaints from the bar.
