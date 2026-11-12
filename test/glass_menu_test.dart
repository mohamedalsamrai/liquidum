import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquidum/liquidum.dart';

void main() {
  Widget app(Widget child) => CupertinoApp(
    home: Stack(
      children: <Widget>[Positioned(left: 20, top: 200, child: child)],
    ),
  );

  testWidgets('a touch opens the menu where UIKit puts it', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(440, 956);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var chosen = '';
    await tester.pumpWidget(
      app(
        GlassButton(
          label: 'Menu',
          menu: <GlassMenuItem>[
            GlassMenuItem(label: 'One', onPressed: () => chosen = 'one'),
            GlassMenuItem(label: 'Two', onPressed: () => chosen = 'two'),
          ],
        ),
      ),
    );
    await tester.tap(find.byType(GlassButton));
    await tester.pumpAndSettle();
    expect(find.text('One'), findsOneWidget);
    // The platter: 250 x 104 at the button's top-left corner.
    final RenderBox glass = tester.renderObject(
      find.ancestor(of: find.text('One'), matching: find.byType(Glass)).first,
    );
    final Rect r = glass.localToGlobal(Offset.zero) & glass.size;
    expect(r.left, closeTo(20, 0.5));
    expect(r.top, closeTo(200, 0.5));
    expect(r.size.width, closeTo(250, 0.5));
    expect(r.size.height, closeTo(104, 0.5));
    await tester.tap(find.text('Two'));
    await tester.pumpAndSettle();
    expect(chosen, 'two');
    expect(find.text('One'), findsNothing);
  });

  Rect glassOf(WidgetTester tester, Finder text) {
    final RenderBox glass = tester.renderObject(
      find.ancestor(of: text, matching: find.byType(Glass)).first,
    );
    return glass.localToGlobal(Offset.zero) & glass.size;
  }

  testWidgets('a submenu grows over the menu and folds back', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(440, 956);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var chosen = '';
    await tester.pumpWidget(
      app(
        GlassButton(
          label: 'Menu',
          menu: <GlassMenuItem>[
            GlassMenuItem(label: 'One', onPressed: () {}),
            GlassMenuItem.submenu(
              label: 'More',
              items: <GlassMenuItem>[
                GlassMenuItem(label: 'Alpha', onPressed: () => chosen = 'a'),
                GlassMenuItem(label: 'Beta', onPressed: () => chosen = 'b'),
              ],
            ),
          ],
        ),
      ),
    );
    await tester.tap(find.byType(GlassButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    expect(find.text('Alpha'), findsOneWidget);
    // Its header (62pt) centered on the row it came from (252..294), where
    // the menu has receded to 0.97 from its top.
    final Rect sub = glassOf(tester, find.text('Alpha'));
    expect(sub.top, closeTo(200 + 73 * 0.97 - 31, 0.5));
    expect(sub.height, closeTo(62 + 10 + 84 + 10, 0.5));
    // The header folds it back.
    await tester.tap(find.text('More').last);
    await tester.pumpAndSettle();
    expect(find.text('Alpha'), findsNothing);
    expect(find.text('One'), findsOneWidget);
    // So does a tap on the menu under it.
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('One'));
    await tester.pumpAndSettle();
    expect(find.text('Alpha'), findsNothing);
    expect(find.text('One'), findsOneWidget);
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Beta'));
    await tester.pumpAndSettle();
    expect(chosen, 'b');
    expect(find.text('One'), findsNothing);
  });

  testWidgets('menus keep on screen as UIKit\'s', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(440, 956);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 62, bottom: 34);
    addTearDown(tester.view.reset);
    final List<GlassMenuItem> items = <GlassMenuItem>[
      GlassMenuItem(label: 'First', onPressed: () {}),
      GlassMenuItem(label: 'Last', onPressed: () {}),
    ];
    await tester.pumpWidget(
      CupertinoApp(
        home: Stack(
          children: <Widget>[
            Positioned(
              right: 20,
              top: 200,
              child: GlassButton(icon: CupertinoIcons.add, menu: items),
            ),
            Positioned(
              left: 20,
              top: 820,
              child: GlassButton(label: 'Bottom', menu: items),
            ),
          ],
        ),
      ),
    );
    // Near the right edge: from the button's right edge.
    await tester.tap(find.byType(GlassButton).first);
    await tester.pumpAndSettle();
    Rect r = glassOf(tester, find.text('First'));
    expect(r.right, closeTo(420, 0.5));
    expect(r.top, closeTo(200, 0.5));
    await tester.tapAt(const Offset(100, 600));
    await tester.pumpAndSettle();
    // Near the bottom: up from the button's bottom, the first item nearest
    // the button.
    await tester.tap(find.byType(GlassButton).last);
    await tester.pumpAndSettle();
    r = glassOf(tester, find.text('First'));
    expect(r.bottom, closeTo(820 + 38.33, 0.5));
    expect(
      tester.getCenter(find.text('First')).dy,
      greaterThan(tester.getCenter(find.text('Last')).dy),
    );
  });

  testWidgets('a finger can slide from the button onto a row', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(440, 956);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var chosen = '';
    await tester.pumpWidget(
      app(
        GlassButton(
          label: 'Menu',
          menu: <GlassMenuItem>[
            GlassMenuItem(label: 'One', onPressed: () => chosen = 'one'),
            GlassMenuItem(label: 'Two', onPressed: () => chosen = 'two'),
          ],
        ),
      ),
    );
    final TestGesture finger = await tester.startGesture(
      tester.getCenter(find.byType(GlassButton)),
    );
    // The menu opens on touch down.
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.text('Two'), findsOneWidget);
    await finger.moveTo(tester.getCenter(find.text('Two')));
    await tester.pump();
    await finger.up();
    await tester.pumpAndSettle();
    expect(chosen, 'two');
    expect(find.text('One'), findsNothing);
  });
}
