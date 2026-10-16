# UIKit reference notes

Source comments from Liquidum 0.1.0, kept here word for word. They name
parts of UIKit's implementation of the iOS 26 tab bar that are not public
API, as they were observed in the iOS 26.5 simulator while Liquidum was
measured against it. From 0.1.1 the shipped source describes the same
things in neutral terms; these notes keep the research. They are not part
of the published package.

Each entry gives the source file, the constant, class or function the
comment documents, and the comment as it was. Line numbers are from the
0.1.0 tag.

## `lib/src/tab_bar/appearance.dart`

### `GlassAppearance._black`, `_white` and `_fillAlpha` (the platter's face color matrix)

Lines 168–173:

```dart
  // The platter's face color matrix (glassBackground): luma mapped from
  // [black, white], chroma kept, then a fill color mixed in; all under the
  // 0.97 SDR holding tone. black = 1.032 L - 0.15 (0.1 to 0.85), white =
  // that + 0.6 (to 1.03 light, 0.9 dark); light fills white at
  // 0.75 - 0.517 L (0.25 to 0.6), dark fills black at 0.25 + 0.367 L (to
  // 0.5).
```

## `lib/src/tab_bar/field.dart`

### `GlassShape.normal`

Lines 30–37:

```dart
  /// Unit direction in which [distance] grows fastest at [p], blended by
  /// [ovalization] (0 to 1) toward the normal of the ellipse inscribed in
  /// [rect].
  ///
  /// A capsule's own normals are straight up or down along its sides and
  /// only turn around the ends; the blend makes them turn continuously all
  /// the way round, as CoreAnimation's SDF layers do with their
  /// `gradientOvalization` (0.5 on the iOS 26 tab bar lens).
```

## `lib/src/tab_bar/glyphs.dart`

### `BarGlyph`

Lines 5–8:

```dart
/// SF Symbols' magnifying glass and xmark as UIKit draws them in its tab
/// bar's search tab and field (iOS 26.5, measured from screenshots): a ring
/// of 0.735 of the glyph's size with a round-capped handle to its corner,
/// and a cross of round-capped strokes. Colored from the [IconTheme].
```

## `lib/src/tab_bar/minimize.dart`

### `GlassTabBarMinimize.fade`

Lines 36–39:

```dart
  /// The crossfade from the tabs to the circle's icon (UIKit's
  /// _UIMagicMorphTransformView): what goes out fades and blurs (radius 4pt
  /// at the end), what comes in the reverse, both squeezed into the
  /// platter's shape.
```

## `lib/src/tab_bar/physics.dart`

### `GlassTabBarPhysics` (class documentation)

Lines 18–22:

```dart
/// The model and its numbers come from UIKit's own tab bar on the iOS 26.5
/// simulator: its lens and flex state logged every frame under scripted
/// touches (398×62pt bar, four tabs), and its settings read at runtime
/// (`_UILiquidLensViewSpec`, `_UIFlexInteractionSpec`). Where UIKit's lens
/// trails the finger through a spring, this lens follows it exactly.
```

### `GlassTabBarPhysics.lensHangTime` and the lift spring

Lines 259–261:

```dart
  // Lift progress: the clear optics (UIKit's liftProgress, 631.65/50.27,
  // critically damped in 0.25s). A quick tap keeps the lens lifted for
  // [lensHangTime] after the finger leaves.
```

### `GlassTabBarPhysics.liftProgress`

Lines 838–839:

```dart
  /// 0 for the frosted resting pill, 1 for clear glass (UIKit's
  /// liftProgress).
```

## `lib/src/tab_bar/spring.dart`

### `GlassSpring.physical`

Lines 18–19:

```dart
  /// A spring given as mass, stiffness and damping, like
  /// `BSSpringAnimationSettings` on iOS.
```

## `lib/src/tab_bar/tab_bar.dart`

### `RenderGlassTabBar._frostHeavySigma`

Lines 2191–2200:

```dart
  // UIKit's platter frosts what is below it, then refracts that: its
  // glassBackground blurs its quarter-scale capture and mixes that into the
  // capture itself, half at the platter's edge and fully 31pt in
  // (inputBlurDistance and inputBlurOpacity), so a point refracted from deep
  // inside comes out deeply frosted. Here the capture is not scaled down: the
  // heavy blur is drawn first, natively, and the backdrop shader's frost
  // pass draws a light one (for the capture's filtering) over it, fading
  // from half at the edge to none at the middle line. The heavy sigma is in
  // points, fitted to UIKit's frost over stripes. (Through a ShaderMask,
  // which would be simpler, Impeller misplaces a backdrop filter.)
```

### `RenderGlassTabBar._reducedFrostSigma`

Lines 2203–2205:

```dart
  // With Reduce Transparency, UIKit blurs far more (its glassBackground's
  // inputBlurRadius goes from 0.67 to 36.9) and fully: a sigma that leaves
  // 40pt blocks as faint as UIKit's do, and no light blur.
```

### `RenderGlassTabBar._ovalization`

Lines 2570:

```dart
  // UIKit's gradientOvalization for the glass's distance field.
```

## `shaders/backdrop.frag`

### File header

Lines 8–10:

```glsl
// The optics are UIKit's, from the layers of its own tab bar on iOS 26.5:
// parameters read from the live layer tree and each stage measured on its
// own over position-coded backdrops.
```

### `kWarp`, `kWarpHeight`

Lines 89–90:

```glsl
// Lens: displacementMap amount at full lift (liftedDisplacement) and the
// height of its CASDFGlassDisplacementEffect.
```

### `kLensInner`, `kLensInnerHeight`, `kLensTone`

Lines 93:

```glsl
// Lens glassBackground: inner refraction amount and height, SDR holding tone.
```

### `kAberrationDepth`, `kAberration`

Lines 97–101:

```glsl
// Lens glassForeground (aberration amount 3.68, offset 38.9, angle -15
// degrees): the image is dispersed over seven taps along a vector that grows
// with the position (x / half width, y / half height); red takes the three
// taps toward one end (1:2:3), blue the mirror, green the middle five
// (1:2:3:2:1). Mixed in fully at the edge, not at all 14pt in.
```

### `kPlatterInner`, `kPlatterInnerHeight`, `kFrostInset`, `kFrostLight`, `kFrostFullDepth`, `kFrostRamp`

Lines 104–111:

```glsl
// Platter glassBackground: inner refraction. Its frost is in the capture
// already, within the platter less this many pixels: the bar draws it
// there before its other passes, a heavy blur (natively) and over it a
// light one (this shader's frost pass), at what the platter holds of the
// light one: half at its edge, none 31pt in (UIKit's inputBlurDistance and
// inputBlurOpacity, which mix its heavy blur into its quarter-scale
// capture), along a power of the depth. The light blur's sigma is in
// points; it and the power are fitted to UIKit's frost over stripes.
```

### `kRestBlur`

Lines 122–123:

```glsl
// The resting selection blurs the glass behind it again (gaussianBlur,
// radius 2 at quarter scale), then applies a color matrix (uPill).
```

### `kContentLens`, `kContentLensHeight`, `kContentMaterialHeight`, `kContentGrowth`

Lines 125–129:

```glsl
// Lifted content (UIKit's contentWrapperDisplacement): the selected tabs, seen
// in the lens, are lensed by two displacement maps of this amount at full
// lift (one of height 11.2, then one of height 14 in the material), each
// pulling inward near the edge.
// UIKit also scales each selected tab by 1.16 about its center at full lift.
```

### `kMaterialFade`

Lines 134–135:

```glsl
// The lens's material is faded in by UIKit's opacityPair filter, at four
// times the lift progress.
```

### `kLight`, `kRimHeight`, `kPlatterRimCurvature`, `kLensRimCurvature`

Lines 140–146:

```glsl
// Rim (CASDFKeyFillHighlightEffect): a key light from up-left and a fill
// from down-right at equal amounts light a 1pt band inside the edge by
// |n.l|, fading toward its inner side by the effect's curvature (platter
// 0.7, lens 0.8); measured alpha = |n.l| (1 - curvature u), u the depth
// over the band, within 1-4% of UIKit's rim at every angle. Its vibrant
// color matrix (uRim, uLensRim) pushes what is below toward a gain of its
// chroma plus a weight of its luma and a lift.
```

### `kPlatterShadow`, `kPlatterShadowReach`, `kLensShadow`, `kLensShadowStrength`, `kLensShadowReach`

Lines 151–156:

```glsl
// Shadows (glassBackground): outside the glass, what is below is multiplied
// by 1 - strength * (a gaussian edge of the outline moved down); the edge's
// sigma is 0.685 of the filter's shadow radius. (offset, sigma, center) in
// points. The strength is opacity * (0.093 + 0.966 fill): the lens's fill
// is black; the platter's adapts to the backdrop (uRim.w). Both fit UIKit's
// within 0.3 levels; the platter's stops where its SDF does.
```

### `kLensTopShade`

Lines 162–166:

```glsl
// Inside, the lens's material darkens what it reads where its shadow's
// edge is not: most just inside its top edge, and none past 15pt in (by
// this much over what is below, wherever the shadow there would be none).
// Fitted to UIKit's lifted lens over white, gray and a position code; its
// glassBackground's inputSDRShadowOpacity (0.111) is the likely source.
```

### `outward()`

Lines 199–202:

```glsl
// Outward direction of the capsule's distance, blended by `oval` toward the
// direction of the point in the capsule's normalized coordinates (x / half
// width, y / half height): UIKit's gradientOvalization, which this matches
// to within 1.3 degrees (median) over its lens's displacement field.
```

### `main()`, the lens pass (the material fading in)

Lines 763–764:

```glsl
    // The material fades in quickly as the lens lifts (UIKit's opacityPair),
    // over the base: the resting selection over the warped backdrop.
```
