import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

/// One of this package's shaders, loaded once and shared.
class ShaderProgram {
  ShaderProgram(this.name);

  /// File name under `shaders/`, like `field.frag`.
  final String name;

  ui.FragmentProgram? _program;
  Future<void>? _loading;

  /// The program, once [load] has finished.
  ui.FragmentProgram? get program => _program;

  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    // The first key is how apps see the asset; the second is how this
    // package sees it when it is the app, as in its own tests.
    final keys = <String>['packages/liquidum/shaders/$name', 'shaders/$name'];
    Object? error;
    StackTrace? stack;
    for (final key in keys) {
      try {
        _program = await ui.FragmentProgram.fromAsset(key);
        return;
      } catch (e, s) {
        error ??= e;
        stack ??= s;
      }
    }
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error!,
        stack: stack,
        library: 'liquidum',
        context: ErrorDescription('while loading the shader $name'),
      ),
    );
  }
}
