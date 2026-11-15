# Contributing to Liquidum

Bug reports, comparisons with UIKit, docs fixes and code are all welcome.

## Before you write code

For anything bigger than a small fix, open an issue or comment on an existing one first, so we can agree on the approach before you spend time on it.

Liquidum is measured against UIKit on iOS 26: sizes, springs, colors and timing come from the native controls. A PR that changes one of those values should show where the new value comes from, usually a capture from iOS next to the Liquidum result. [doc/comparison](doc/comparison) has plenty of examples.

## Setup

You need Flutter 3.47 or newer.

```sh
git clone https://github.com/<your-username>/liquidum
cd liquidum
flutter pub get
cd example
flutter run
```

## Opening a pull request

Run the same checks CI runs:

```sh
dart format .
flutter analyze
flutter test
```

Then:

- Open the PR against `main`, unless the issue asks for another branch.
- Add tests for behavior changes.
- Document public API with `///` comments.
- For anything users will notice, add a line under `## Unreleased` in [CHANGELOG.md](CHANGELOG.md). Start it with `New:` for new API and `Breaking:` for breaking changes.

Every PR also gets an automated review from CodeRabbit, which follows [AGENTS.md](AGENTS.md). Treat its comments as suggestions.

## Labels

Labels follow the same naming as [flutter/flutter](https://github.com/flutter/flutter/labels):

| Label | Meaning |
| --- | --- |
| `P0` to `P3` | Priority, `P0` being the most urgent |
| `c: ...` | Category: bug, crash, new feature, proposal... |
| `a: ...` | Area of the library: tab bar, glass, lens, menus... |
| `d: ...` | Documentation |
| `platform-...` | Where the issue shows up |
| `r: ...` | Why an issue was closed |

New issues start with `in triage`. An issue marked `waiting for response` is closed if its author doesn't reply within 21 days.
