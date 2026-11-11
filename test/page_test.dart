import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquidum/liquidum.dart';

void main() {
  // UIKit's iPhone 17 Pro Max: 440 x 956, status bar 62, home indicator 34.
  Future<void> pump(WidgetTester tester, Widget page) async {
    tester.view.physicalSize = const Size(1320, 2868);
    tester.view.devicePixelRatio = 3;
    tester.view.padding = const FakeViewPadding(top: 186, bottom: 102);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(CupertinoApp(home: page));
    await tester.pump();
  }

  List<Rect> glass(WidgetTester tester) => <Rect>[
    for (final Element e in find.byType(Glass).evaluate())
      tester.getRect(find.byWidget(e.widget)),
  ];

  testWidgets('the bars sit where UIKit puts them', (
    WidgetTester tester,
  ) async {
    late EdgeInsets padding;
    await pump(
      tester,
      GlassPage(
        title: 'Detail',
        onBack: () {},
        actions: <GlassBarItem>[
          GlassBarItem(icon: CupertinoIcons.ellipsis, onPressed: () {}),
          GlassBarItem(icon: CupertinoIcons.add, onPressed: () {}),
        ],
        toolbar: <GlassBarItem>[
          GlassBarItem(icon: CupertinoIcons.trash, onPressed: () {}),
          const GlassBarItem.space(),
          GlassBarItem(icon: CupertinoIcons.share, onPressed: () {}),
          const GlassBarItem.space(),
          GlassBarItem(label: 'Done', prominent: true, onPressed: () {}),
        ],
        child: Builder(
          builder: (BuildContext context) {
            padding = MediaQuery.paddingOf(context);
            return const SizedBox.expand();
          },
        ),
      ),
    );
    final List<Rect> rects = glass(tester);
    // The back circle, and the two icons on one capsule (UIKit's 99.33 with
    // its ellipsis's wider box).
    expect(rects, contains(const Rect.fromLTWH(20, 62, 44, 44)));
    final Rect group = rects.firstWhere(
      (Rect r) => r.top == 62 && r.left > 300,
    );
    expect(group.right, 420);
    expect(group.width, closeTo(4 + 37.33 + 16 + 37.33 + 4, 0.01));
    // The toolbar: circles 28pt from the sides and bottom, 48pt tall.
    expect(rects, contains(const Rect.fromLTWH(28, 880, 48, 48)));
    expect(rects, contains(const Rect.fromLTWH(196, 880, 48, 48)));
    final Rect done = rects.firstWhere(
      (Rect r) => r.top == 880 && r.right == 412,
    );
    expect(done.height, 48);
    // The title, centered on the platters' row.
    expect(tester.getCenter(find.text('Detail')).dx, 220);
    expect(tester.getCenter(find.text('Detail')).dy, 84);
    // The content scrolls under bars 116pt and 76pt deep.
    expect(padding.top, 116);
    expect(padding.bottom, 76);
  });

  testWidgets('labels get platters of their own; items tap', (
    WidgetTester tester,
  ) async {
    var edits = 0;
    var adds = 0;
    await pump(
      tester,
      GlassPage(
        title: 'List',
        actions: <GlassBarItem>[
          GlassBarItem(icon: CupertinoIcons.add, onPressed: () => adds++),
          GlassBarItem(label: 'Edit', onPressed: () => edits++),
        ],
        child: const SizedBox.expand(),
      ),
    );
    final List<Rect> rects = glass(tester);
    expect(rects.length, 2);
    // The icon alone: a 44pt circle, 12pt before the label's platter.
    final Rect edit = rects.firstWhere((Rect r) => r.right == 420);
    final Rect add = rects.firstWhere((Rect r) => r != edit);
    expect(add.size, const Size(44, 44));
    expect(add.right, edit.left - 12);
    expect(edit.height, 44);
    await tester.tap(find.bySemanticsLabel('Edit'));
    await tester.tapAt(add.center);
    await tester.pumpAndSettle();
    expect(edits, 1);
    expect(adds, 1);
  });

  testWidgets('a large title scrolls away into the bar', (
    WidgetTester tester,
  ) async {
    final ScrollController scroll = ScrollController();
    addTearDown(scroll.dispose);
    await pump(
      tester,
      GlassPage(
        title: 'Inbox',
        largeTitle: true,
        child: ListView(
          controller: scroll,
          children: <Widget>[
            for (var i = 0; i < 40; i++)
              SizedBox(height: 44, child: Text('$i')),
          ],
        ),
      ),
    );
    final Finder titles = find.text('Inbox');
    expect(titles, findsNWidgets(2));
    // The large title: 34pt bold at x 20, under the bar.
    final Rect large = tester.getRect(titles.first);
    expect(large.left, 20);
    expect(large.top, closeTo(120, 1));
    // The content starts under the large title's row.
    expect(tester.getTopLeft(find.text('0')).dy, 168);
    scroll.jumpTo(100);
    await tester.pumpAndSettle();
    expect(tester.getRect(titles.first).top, closeTo(20, 1));
  });

  testWidgets('the search field makes room for a close button', (
    WidgetTester tester,
  ) async {
    final TextEditingController text = TextEditingController();
    addTearDown(text.dispose);
    await pump(
      tester,
      GlassPage(
        title: 'List',
        searchController: text,
        child: const SizedBox.expand(),
      ),
    );
    expect(glass(tester), contains(const Rect.fromLTWH(28, 880, 384, 48)));
    await tester.tap(find.byType(CupertinoTextField));
    await tester.pumpAndSettle();
    final List<Rect> open = glass(tester);
    expect(open, contains(const Rect.fromLTWH(28, 880, 324, 48)));
    expect(open, contains(const Rect.fromLTWH(364, 880, 48, 48)));
    await tester.enterText(find.byType(CupertinoTextField), 'abc');
    await tester.tap(find.bySemanticsLabel('Close'));
    await tester.pumpAndSettle();
    expect(text.text, '');
    expect(glass(tester), contains(const Rect.fromLTWH(28, 880, 384, 48)));
  });
}
