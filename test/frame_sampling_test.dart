import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquidum/liquidum.dart';
import 'package:liquidum/src/frame_sampler.dart';

/// A long list under the glass, to draw frames by scrolling it.
Widget _list() => ListView.builder(
  itemCount: 200,
  itemExtent: 44,
  itemBuilder: (BuildContext context, int i) => Text('row $i'),
);

void main() {
  // Each owner of a sampler: the glass over a scrolling list, and its
  // throttle.
  final owners = <String, (Widget, Duration)>{
    'GlassTabBar': (
      CupertinoApp(
        home: Stack(
          children: <Widget>[
            _list(),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: GlassTabBar(
                items: const <GlassTabItem>[
                  GlassTabItem(icon: Icon(CupertinoIcons.house), label: 'A'),
                  GlassTabItem(icon: Icon(CupertinoIcons.bell), label: 'B'),
                ],
                selectedIndex: 0,
                onSelected: (_) {},
              ),
            ),
          ],
        ),
      ),
      const Duration(milliseconds: 50),
    ),
    'GlassBrightness': (
      CupertinoApp(
        home: Stack(
          children: <Widget>[
            _list(),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 60,
              child: GlassBrightness(
                builder: (BuildContext context, double dark, _) =>
                    const SizedBox.expand(),
              ),
            ),
          ],
        ),
      ),
      const Duration(milliseconds: 250),
    ),
  };

  late List<DateTime> samples;
  late List<DateTime> frames;
  var recording = false;

  setUp(() {
    samples = <DateTime>[];
    frames = <DateTime>[];
  });

  tearDown(() {
    FrameSampler.debugOnSample = null;
    recording = false;
  });

  for (final MapEntry<String, (Widget, Duration)> owner in owners.entries) {
    final (Widget app, Duration interval) = owner.value;

    // Builds the app, lets it settle, and counts its sampler's samples (and
    // the frames drawn) from then on.
    Future<void> start(WidgetTester tester) async {
      final binding = tester.binding;
      FrameSampler.debugOnSample = (FrameSampler sampler) {
        if (sampler.interval == interval) {
          samples.add(binding.clock.now());
        }
      };
      if (!recording) {
        binding.addPersistentFrameCallback((_) {
          if (recording) {
            frames.add(binding.clock.now());
          }
        });
      }
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();
      await tester.pump(interval * 2);
      samples.clear();
      frames.clear();
      recording = true;
    }

    Future<void> scroll(WidgetTester tester) async {
      await tester.fling(find.byType(ListView), const Offset(0, -400), 2500);
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    group(owner.key, () {
      testWidgets('takes no samples while no frames are drawn', (
        WidgetTester tester,
      ) async {
        await start(tester);
        for (var i = 0; i < 50; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(frames, isEmpty);
        expect(samples, isEmpty);
      });

      testWidgets('samples during a scroll, no faster than its throttle', (
        WidgetTester tester,
      ) async {
        await start(tester);
        await scroll(tester);
        expect(frames.length, greaterThan(30));
        expect(samples.length, greaterThan(2));
        for (var i = 1; i < samples.length; i++) {
          expect(
            samples[i].difference(samples[i - 1]),
            greaterThanOrEqualTo(interval),
          );
        }
      });

      testWidgets('takes one more sample after the last frame', (
        WidgetTester tester,
      ) async {
        await start(tester);
        await scroll(tester);
        await tester.pumpAndSettle();
        // A frame sampled at once, then one within the throttle after it,
        // which only a sample after the last frame measures.
        tester.binding.scheduleFrame();
        await tester.pump(interval * 2);
        tester.binding.scheduleFrame();
        await tester.pump(const Duration(milliseconds: 10));
        final DateTime lastFrame = frames.last;
        await tester.pump(interval * 2);
        expect(samples.last.isBefore(lastFrame), isFalse);
        // And then nothing.
        final int taken = samples.length;
        for (var i = 0; i < 30; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(samples.length, taken);
      });

      testWidgets('takes none while the app is not resumed, one on resume', (
        WidgetTester tester,
      ) async {
        await start(tester);
        final binding = tester.binding;
        // Inactive, frames are still drawn, and ignored.
        binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        await scroll(tester);
        await tester.pumpAndSettle();
        expect(frames, isNotEmpty);
        binding
          ..handleAppLifecycleStateChanged(AppLifecycleState.hidden)
          ..handleAppLifecycleStateChanged(AppLifecycleState.paused);
        for (var i = 0; i < 30; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(samples, isEmpty);
        binding
          ..handleAppLifecycleStateChanged(AppLifecycleState.hidden)
          ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
          ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pump();
        expect(samples, hasLength(1));
        for (var i = 0; i < 30; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(samples, hasLength(1));
        // Back from inactive alone, where no frame comes by itself.
        binding
          ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
          ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pump();
        expect(samples, hasLength(2));
      });
    });
  }

  testWidgets('over a still backdrop, the bar stops reading it', (
    WidgetTester tester,
  ) async {
    // A real backdrop, read for real: each reading of an unchanged backdrop
    // must not draw the frames that call for the next one.
    var taken = 0;
    FrameSampler.debugOnSample = (FrameSampler sampler) {
      if (sampler.interval == const Duration(milliseconds: 50)) {
        taken++;
      }
    };
    await tester.pumpWidget(
      CupertinoApp(
        home: GlassTabScaffold(
          tabs: <GlassTab>[
            GlassTab(icon: CupertinoIcons.house, label: 'A', page: _list()),
            GlassTab(icon: CupertinoIcons.bell, label: 'B', page: _list()),
          ],
        ),
      ),
    );
    // Frames, with the snapshots' real work let through between them.
    Future<void> run(int frames) async {
      for (var i = 0; i < frames; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 2)),
        );
      }
    }

    await run(120);
    expect(taken, greaterThan(0));
    final int settled = taken;
    await run(120);
    expect(taken, settled);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
