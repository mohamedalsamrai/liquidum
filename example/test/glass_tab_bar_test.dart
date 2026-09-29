import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquidum/liquidum.dart';
import 'package:liquidum_example/glass_tab_bar.dart';

void main() {
  const items = <GlassTabItem>[
    GlassTabItem(
      icon: CupertinoIcons.house_fill,
      label: 'Home',
      symbol: 'house.fill',
    ),
    GlassTabItem(
      icon: CupertinoIcons.square_grid_2x2_fill,
      label: 'New',
      symbol: 'square.grid.2x2.fill',
    ),
    GlassTabItem(
      icon: CupertinoIcons.dot_radiowaves_left_right,
      label: 'Radio',
      symbol: 'dot.radiowaves.left.and.right',
    ),
    GlassTabItem(
      icon: CupertinoIcons.music_albums_fill,
      label: 'Library',
      symbol: 'music.note.square.stack.fill',
    ),
  ];

  testWidgets('the lens lifts, tracks the finger, and selects on release', (
    WidgetTester tester,
  ) async {
    var selected = 0;
    await tester.pumpWidget(
      CupertinoApp(
        home: Center(
          child: SizedBox(
            width: 398,
            child: StatefulBuilder(
              builder: (BuildContext context, StateSetter setState) =>
                  GlassTabBar(
                    items: items,
                    selectedIndex: selected,
                    onSelected: (int i) => setState(() => selected = i),
                  ),
            ),
          ),
        ),
      ),
    );
    final Rect bar = tester.getRect(find.byType(GlassTabBar));
    expect(find.byType(Glass), findsOneWidget);

    final TestGesture finger = await tester.startGesture(
      Offset(bar.left + 60, bar.center.dy),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(Glass), findsNWidgets(2), reason: 'lens lifted');

    // After the initial glide the lens is exactly under the finger.
    for (var x = 60.0; x <= 250; x += 10) {
      await finger.moveTo(Offset(bar.left + x, bar.center.dy));
      await tester.pump(const Duration(milliseconds: 16));
    }
    final Rect lens = tester.getRect(find.byType(Glass).last);
    expect(lens.center.dx, moreOrLessEquals(bar.left + 250, epsilon: 0.5));
    expect(lens.height, greaterThan(GlassTabBar.height));

    await finger.up();
    await tester.pumpAndSettle();
    expect(selected, 2);
    expect(find.byType(Glass), findsOneWidget, reason: 'lens dropped');
  });
}
