# Notes for AI agents and reviewers

Liquidum is a Flutter package that rebuilds UIKit's iOS 26 glass from measurements of the native controls: the tab bar, navigation bars and toolbars, buttons, switches, sliders, segmented controls, menus, alerts, sheets and the date picker. Every change is judged by how close it gets to UIKit and whether it keeps the package fast and stable.

CodeRabbit reads this file when it reviews pull requests. Coding agents working in the repository should follow it too.

## Commands

```sh
flutter pub get
dart format .
flutter analyze
flutter test
```

CI also runs `flutter pub publish --dry-run`. The example app is in `example/`.

## What matters most

- **Matching UIKit.** Sizes, springs, colors, thresholds and timings are measured from iOS 26. A change to one of these values should say where the new value comes from: a capture, a measurement or a UIKit API. Point it out when it doesn't.
- **Public API.** Everything exported from `lib/liquidum.dart` is public and follows semantic versioning. `lib/liquidum_debug.dart` is for the comparison harness and isn't covered by semantic versioning. Flag changes that break existing public code without a `Breaking:` line in CHANGELOG.md.
- **Changelog.** Changes users will notice need a line under `## Unreleased` in CHANGELOG.md. New API starts with `New:`, breaking changes with `Breaking:`.
- **Docs.** Every public member needs a `///` doc comment that says what it does. For a value or behavior taken from UIKit, the comment should name the UIKit behavior it matches.
- **Tests.** Behavior changes need tests in `test/`. A new test should fail if the fix is reverted.

## Rendering and performance

- Nothing in `paint` that could be done once: reuse `Paint`, `Path` and shader objects, and don't load shaders or lay out text while painting.
- Shaders live in `shaders/` and are loaded through `ShaderProgram`. Prefer the name-based uniform accessors (`getUniformVec4`, `getUniformVec4Array`). Where a shader is still set by index with `setFloat`, the indices must follow the order the uniforms are declared in its `.frag` file. Flag a change to a shader's uniforms that isn't matched on the Dart side, or the other way around.
- Backdrop sampling follows drawn frames. Flag timers, polling, or anything that keeps scheduling frames while nothing on screen changes.
- Every `AnimationController`, `Ticker`, `ScrollController`, `FocusNode`, `OverlayEntry` and listener a `State` creates must be disposed or removed.
- Rendering has to work on iOS (Impeller on Metal) and on Android (Impeller on Vulkan and on OpenGL ES).

## Accessibility and layout

- Follow the accessibility settings the way UIKit does: Reduce Motion, Bold Text, Increase Contrast and text scaling, read from `MediaQuery`.
- Interactive widgets need `Semantics` with a label and the right flags and actions.
- Layouts must mirror in right-to-left apps: use `Directionality`, `EdgeInsetsDirectional` and `AlignmentDirectional` rather than fixed left and right.

## Reviewing a pull request

- Look for regressions in other widgets that share the changed code. The glass, the lens and the springs are used widely.
- Look for cases the change doesn't handle, and suggest a test that shows the gap.
- Suggest simpler code when it really is simpler.
- Don't report formatting or analyzer findings. CI runs `dart format` and `flutter analyze`.
- Don't report style preferences that aren't in this file.
- Base the summary on the diff, not on the PR description. Keep it short and neutral.
