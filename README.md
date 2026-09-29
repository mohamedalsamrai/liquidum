# liquidum

Liquid glass as a material for Flutter. This is a reconstruction of the iOS 26
look, not Apple's renderer. Its parameters are fitted to native iOS 26 glass,
which was measured in the iOS 26.5 simulator against ramp, stripe and color
backgrounds.

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
  (dark glass turns light).
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

`example/` builds an iOS 26 style tab bar from these pieces. Press and slide to
move the clear lens between tabs, then release to select the tab under it. Judge
motion in profile or release mode, because debug builds are much slower on
device.

The switch at the top of the example swaps in Apple's own tab bar
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
- The Android GLES path follows the engine's y-flip guidance but is untested.
