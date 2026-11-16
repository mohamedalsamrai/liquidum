// Drives the showcase for the README's screenshots: runs the steps in
// `<tmp>/comparison.txt` with touches made in the app (no real input), then
// writes `<tmp>/ready.txt`. Steps, separated by `;`, in points:
//
//   tap x y | dtap x y (a double tap) | press x y s (hold s seconds) |
//   drag x0 y0 x1 y1 s | slide x0 y0 x1 y1 s (a drag that stays down) |
//   wait s
//
// `.research/readme_shots.sh` launches it on the simulator once per scene
// and takes the screenshots.

import 'dart:async';
import 'dart:io';

// ignore: deprecated_member_use
import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:liquidum/liquidum.dart';

import 'showcase.dart' as showcase;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Glass.precache();
  final File config = File('${Directory.systemTemp.path}/comparison.txt');
  final String steps = config.existsSync() ? config.readAsStringSync() : '';
  final File ready = File('${Directory.systemTemp.path}/ready.txt');
  if (ready.existsSync()) {
    ready.deleteSync();
  }
  runApp(const showcase.ShowcaseApp());
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    await _wait(1.5);
    await _Touches().run(steps);
    await _wait(1.5);
    ready.writeAsStringSync('ready');
  });
}

Future<void> _wait(double seconds) =>
    Future<void>.delayed(Duration(milliseconds: (seconds * 1000).round()));

class _Touches {
  int _pointer = 1000;
  final Stopwatch _clock = Stopwatch()..start();

  void _send(PointerEvent e) => GestureBinding.instance.handlePointerEvent(e);

  Future<void> run(String script) async {
    for (final String step in script.split(';')) {
      final List<String> p = step.trim().split(RegExp(r'\s+'));
      if (p.first.isEmpty) {
        continue;
      }
      final List<double> n = p.skip(1).map(double.parse).toList();
      switch (p.first) {
        case 'wait':
          await _wait(n[0]);
        case 'tap':
          await _hold(Offset(n[0], n[1]), 0.08);
        case 'dtap':
          await _hold(Offset(n[0], n[1]), 0.06);
          await _wait(0.08);
          await _hold(Offset(n[0], n[1]), 0.06);
        case 'press':
          await _hold(Offset(n[0], n[1]), n[2]);
        case 'drag':
          await _drag(Offset(n[0], n[1]), Offset(n[2], n[3]), n[4]);
        case 'slide':
          await _drag(
            Offset(n[0], n[1]),
            Offset(n[2], n[3]),
            n[4],
            lift: false,
          );
      }
    }
  }

  Future<void> _hold(Offset at, double seconds) async {
    final int id = _pointer++;
    _send(
      PointerDownEvent(
        pointer: id,
        position: at,
        timeStamp: _clock.elapsed,
        kind: PointerDeviceKind.touch,
      ),
    );
    await _wait(seconds);
    _send(
      PointerUpEvent(
        pointer: id,
        position: at,
        timeStamp: _clock.elapsed,
        kind: PointerDeviceKind.touch,
      ),
    );
  }

  Future<void> _drag(
    Offset from,
    Offset to,
    double seconds, {
    bool lift = true,
  }) async {
    final int id = _pointer++;
    _send(
      PointerDownEvent(
        pointer: id,
        position: from,
        timeStamp: _clock.elapsed,
        kind: PointerDeviceKind.touch,
      ),
    );
    final int steps = (seconds * 60).ceil().clamp(1, 600);
    Offset last = from;
    for (var i = 1; i <= steps; i++) {
      await _wait(seconds / steps);
      final Offset at = Offset.lerp(from, to, i / steps)!;
      _send(
        PointerMoveEvent(
          pointer: id,
          position: at,
          delta: at - last,
          timeStamp: _clock.elapsed,
          kind: PointerDeviceKind.touch,
        ),
      );
      last = at;
    }
    if (!lift) {
      return;
    }
    _send(
      PointerUpEvent(
        pointer: id,
        position: to,
        timeStamp: _clock.elapsed,
        kind: PointerDeviceKind.touch,
      ),
    );
  }
}
