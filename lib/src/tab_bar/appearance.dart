import 'dart:ui' show Brightness, Rect;

import 'spring.dart';

/// How a glass tab bar adapts to what is behind it, as UIKit's does (iOS
/// 26.5 simulator, measured from its layers over stepped backdrops).
///
/// UIKit reads the backdrop's mean luma (Rec. 709 on its colors) around
/// the bar, about every frame, and keeps a light or a dark
/// appearance with hysteresis. The glass's color inputs follow the luma and
/// the appearance on a critically damped 0.5s spring; the resting
/// selection's on a 0.24s one; the symbols and labels switch at once.
class GlassAppearance {
  GlassAppearance({Brightness system = Brightness.light}) : _system = system {
    _dark = system == Brightness.dark;
    _luma = _dark ? 0 : 1;
    _snap();
  }

  // ---------------------------------------------------------------- samples

  /// Where UIKit reads the backdrop: its mean luma over the bar's container
  /// (the screen's width, from the bar's top to the screen's bottom) grown
  /// by the glass's 12.4pt margin. For a bar laid out 21pt from the screen's
  /// sides and bottom, that is the bar grown by 21pt to the sides and below
  /// and 12.4pt above.
  static Rect sampleArea(Rect bar) => Rect.fromLTRB(
    bar.left - 21,
    bar.top - 12.4,
    bar.right + 21,
    bar.bottom + 21,
  );

  // ----------------------------------------------------------------- switch

  // The luma at which UIKit turns its bar dark, and back light: with the
  // system in light mode, below 0.210 and above 0.492; in dark mode, below
  // 0.584 and above 0.867.
  static const double _toDark = 0.210, _toLight = 0.492;
  static const double _toDarkInDarkMode = 0.584, _toLightInDarkMode = 0.867;

  Brightness _system;
  late bool _dark;
  late double _luma;
  bool _sampled = false;

  /// Whether the glass is in its dark appearance.
  bool get isDark => _dark;

  /// The backdrop's luma, as last sampled.
  double get luma => _luma;

  // The glass's inputs follow the luma in steps of 1/32 (UIKit rounds it);
  // the switch between appearances, the luma itself.
  double get _stepped => (_luma * 32).round() / 32;

  /// The system's appearance: the bar's own until the backdrop says
  /// otherwise.
  set system(Brightness value) {
    if (value == _system) {
      return;
    }
    _system = value;
    if (!_sampled) {
      _dark = value == Brightness.dark;
      _snap();
    } else {
      _decide();
      _aim();
    }
  }

  // UIKit acts on a change behind the bar 50-90ms after it: the symbols
  // switch, and a frame later the glass starts moving. Readings here take
  // effect 50ms after the frame that receives them, which with sampling
  // every 50ms comes to about the same.
  static const double _latency = 0.05;
  static const double _glassLag = 1 / 60;
  final List<(double?, double)> _pending = <(double?, double)>[];
  double? _aimAt;

  /// A new reading of the backdrop's luma under the bar. The first one
  /// takes effect at once; later ones after a moment, and animate.
  void sample(double luma) {
    debugOnChange?.call(this, 'sample ${luma.toStringAsFixed(4)}');
    if (!_sampled) {
      _sampled = true;
      _luma = luma;
      _decide();
      _snap();
      return;
    }
    _pending.add((null, luma));
  }

  /// Whether the appearance follows the backdrop. When false, it keeps the
  /// [system]'s, and only the glass's colors follow the backdrop's luma.
  set adaptive(bool value) {
    if (value == _adaptive) {
      return;
    }
    _adaptive = value;
    if (!_sampled) {
      _dark = _system == Brightness.dark;
      _snap();
    } else {
      _decide();
      _aim();
    }
  }

  bool _adaptive = true;

  void _decide() {
    final bool darkMode = _system == Brightness.dark;
    if (!_adaptive) {
      _dark = darkMode;
      return;
    }
    final double toDark = darkMode ? _toDarkInDarkMode : _toDark;
    final double toLight = darkMode ? _toLightInDarkMode : _toLight;
    if (_dark && _luma > toLight) {
      _dark = false;
    } else if (!_dark && _luma < toDark) {
      _dark = true;
    }
  }

  // ----------------------------------------------------------------- values

  // The platter's face color matrix (glassBackground): luma mapped from
  // [black, white], chroma kept, then a fill color mixed in; all under the
  // 0.97 SDR holding tone. black = 1.032 L - 0.15 (0.1 to 0.85), white =
  // that + 0.6 (to 1.03 light, 0.9 dark); light fills white at
  // 0.75 - 0.517 L (0.25 to 0.6), dark fills black at 0.25 + 0.367 L (to
  // 0.5).
  static double _black(double l) => (1.032 * l - 0.15).clamp(0.1, 0.85);
  static double _white(double l, bool dark) =>
      (1.032 * l - 0.15 + 0.6).clamp(0.0, dark ? 0.9 : 1.03);
  static double _fillAlpha(double l, bool dark) => dark
      ? (0.25 + 0.367 * l).clamp(0.25, 0.5)
      : (0.75 - 0.517 * l).clamp(0.25, 0.6);

  // The platter's shadow: opacity * (0.093 + 0.966 fill). Light: 0.46875,
  // a black fill of 0.3, less over brighter backdrops, 0.05 over nearly
  // white ones; dark: 0.38125, no fill.
  static double _shadow(double l, bool dark) {
    if (dark) {
      return 0.38125 * 0.093;
    }
    final double fill = l > 0.935
        ? 0.05
        : 0.3 - 0.224 * (l - 0.385).clamp(0.0, 1.0);
    return 0.46875 * (0.093 + 0.966 * fill);
  }

  // The rims' vibrant color matrices, as (chroma gain, luma weight, lift):
  // what is below goes to gain (c - L) + weight L + lift.
  static const List<double> _platterRimLight = <double>[1.5, 0.1, 0.9];
  static const List<double> _platterRimDark = <double>[3.0, 1.35, 0.15];
  static const List<double> _lensRimLight = <double>[1.5, 0.4374, 1.125];
  static const List<double> _lensRimDark = <double>[1.5, 0.5, 0.75];

  // The resting selection's color matrix, the same way.
  static const List<double> _pillLight = <double>[1.2, 1.1294, -0.2];
  static const List<double> _pillDark = <double>[1.116, 0.958, 0.135];

  // Normal symbols and labels, through a vibrant matrix over the glass
  // below them: its chroma at a luma weight plus a lift. (Selected ones are
  // half of it plus the tint, less 0.5 in the light appearance; the tab bar
  // sets that with the tint.)
  static const List<double> _symbolLight = <double>[0.1, 0];
  static const List<double> _symbolDark = <double>[0.05, 0.95];

  static GlassSpring _glass() =>
      GlassSpring(response: 0.5, dampingRatio: 1, tolerance: 1e-4);
  static GlassSpring _quick() =>
      GlassSpring(response: 0.24, dampingRatio: 1, tolerance: 1e-4);

  // black, white, fill alpha, fill gray, shadow strength, platter rim x3,
  // lens rim x3.
  final List<GlassSpring> _glassValues = List<GlassSpring>.generate(
    11,
    (_) => _glass(),
  );
  final List<GlassSpring> _pillValues = List<GlassSpring>.generate(
    3,
    (_) => _quick(),
  );

  List<double> get _glassTargets => <double>[
    _black(_stepped),
    _white(_stepped, _dark),
    _fillAlpha(_stepped, _dark),
    if (_dark) 0 else 1,
    _shadow(_stepped, _dark),
    ...(_dark ? _platterRimDark : _platterRimLight),
    ...(_dark ? _lensRimDark : _lensRimLight),
  ];

  void _aim() {
    final List<double> glass = _glassTargets;
    for (var i = 0; i < glass.length; i++) {
      _glassValues[i].target = glass[i];
    }
    final List<double> pill = _dark ? _pillDark : _pillLight;
    for (var i = 0; i < pill.length; i++) {
      _pillValues[i].target = pill[i];
    }
  }

  void _snap() {
    final List<double> glass = _glassTargets;
    for (var i = 0; i < glass.length; i++) {
      _glassValues[i].snap(glass[i]);
    }
    final List<double> pill = _dark ? _pillDark : _pillLight;
    for (var i = 0; i < pill.length; i++) {
      _pillValues[i].snap(pill[i]);
    }
  }

  double? _now;

  /// Called after every [tick] and [sample], for logging.
  static void Function(GlassAppearance appearance, String event)? debugOnChange;

  /// Advances the springs to [now] (seconds). Returns whether anything is
  /// still moving.
  bool tick(double now) {
    final double dt = _now == null ? 0 : (now - _now!).clamp(0.0, 0.1);
    _now = now;
    for (var i = 0; i < _pending.length; i++) {
      if (_pending[i].$1 == null) {
        _pending[i] = (now + _latency, _pending[i].$2);
      }
    }
    while (_pending.isNotEmpty && _pending.first.$1! <= now) {
      _luma = _pending.removeAt(0).$2;
      _decide();
      _aimAt = now + _glassLag;
    }
    if (_aimAt != null && now >= _aimAt!) {
      _aimAt = null;
      _aim();
    }
    var moving = _pending.isNotEmpty || _aimAt != null;
    for (final GlassSpring s in <GlassSpring>[
      ..._glassValues,
      ..._pillValues,
    ]) {
      s.step(dt);
      moving |= !s.isSettled;
    }
    debugOnChange?.call(this, 'tick');
    return moving;
  }

  /// The platter's face: luma black and white points, fill alpha and gray.
  (double, double, double, double) get face => (
    _glassValues[0].value,
    _glassValues[1].value,
    _glassValues[2].value,
    _glassValues[3].value,
  );

  /// The platter shadow's strength.
  double get shadow => _glassValues[4].value;

  /// The platter's and the lens's rim matrices.
  (double, double, double) get platterRim =>
      (_glassValues[5].value, _glassValues[6].value, _glassValues[7].value);
  (double, double, double) get lensRim =>
      (_glassValues[8].value, _glassValues[9].value, _glassValues[10].value);

  /// The resting selection's matrix.
  (double, double, double) get pill =>
      (_pillValues[0].value, _pillValues[1].value, _pillValues[2].value);

  /// Normal symbols' luma weight and lift.
  (double, double) get symbol {
    final List<double> s = _dark ? _symbolDark : _symbolLight;
    return (s[0], s[1]);
  }
}
