import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquidum/liquidum.dart';

// UIKit's edit menu (iOS 26.5, iPhone 17 Pro Max): a 46pt capsule 15pt
// below the selection (above it when there is no room below), its list
// centered on the selection's middle and kept 20pt from the screen's
// sides; it grows from 0.2 about the selection's middle (omega 22.8,
// damping 0.85: 0.454 at 47ms, 0.838 at 112ms).
void main() {
  late List<String> chosen;
  late ContextMenuController controller;

  Future<BuildContext> show(WidgetTester tester) async {
    tester.view.physicalSize = const Size(440, 956);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 62, bottom: 34);
    addTearDown(tester.view.reset);
    chosen = <String>[];
    controller = ContextMenuController();
    late BuildContext context;
    await tester.pumpWidget(
      CupertinoApp(
        home: Builder(
          builder: (BuildContext c) {
            context = c;
            return const ColoredBox(color: Color(0xFFFFFFFF));
          },
        ),
      ),
    );
    return context;
  }

  List<GlassMenuItem> items(List<String> labels) => <GlassMenuItem>[
    for (final String l in labels)
      GlassMenuItem(label: l, onPressed: () => chosen.add(l)),
  ];

  void open(BuildContext context, Offset at, List<GlassMenuItem> items) {
    controller.show(
      context: context,
      contextMenuBuilder: (BuildContext context) => GlassEditMenu(
        anchors: TextSelectionToolbarAnchors(primaryAnchor: at),
        items: items,
      ),
    );
  }

  // The capsule's glass (the menu's, or its copy's while it hides).
  Rect capsule(WidgetTester tester) => tester.getRect(
    find
        .descendant(
          of: find.byType(GlassEditMenu),
          matching: find.byType(Glass),
        )
        .first,
  );

  Future<void> frames(WidgetTester tester, int n) async {
    for (var i = 0; i < n; i++) {
      await tester.pump(const Duration(microseconds: 16667));
    }
  }

  testWidgets('it sits 15pt below the point, centered on it', (
    WidgetTester tester,
  ) async {
    final BuildContext context = await show(tester);
    open(context, const Offset(220, 480), items(<String>['A', 'B', 'C']));
    await tester.pumpAndSettle();
    final Rect r = capsule(tester);
    expect(r.top, 495);
    expect(r.height, 46);
    // Its list (the glass less 8pt) centered on the point.
    expect(r.left + (r.width - 8) / 2, closeTo(220, 0.01));
    expect(find.bySemanticsLabel('B'), findsOneWidget);
    controller.remove();
    await tester.pumpAndSettle();
  });

  testWidgets('it grows from 0.2 about the point as UIKit\'s', (
    WidgetTester tester,
  ) async {
    final BuildContext context = await show(tester);
    open(context, const Offset(220, 480), items(<String>['A', 'B', 'C']));
    await tester.pump();
    await tester.pumpAndSettle();
    final double full = capsule(tester).width;
    controller.remove();
    await tester.pumpAndSettle();
    open(context, const Offset(220, 480), items(<String>['A', 'B', 'C']));
    await tester.pump();
    // UIKit's scale 47ms and 112ms in (its first frame is the start).
    await frames(tester, 3);
    final Rect early = capsule(tester);
    expect(early.width / full, closeTo(0.454, 0.06));
    expect(early.top, closeTo(495, 0.01));
    expect(early.left + early.width * 0.5, lessThan(232));
    await frames(tester, 4);
    expect(capsule(tester).width / full, closeTo(0.838, 0.05));
    controller.remove();
    await tester.pumpAndSettle();
  });

  testWidgets('near the bottom it goes above; near the side it keeps 20pt', (
    WidgetTester tester,
  ) async {
    final BuildContext context = await show(tester);
    open(context, const Offset(30, 870), items(<String>['A', 'B', 'C']));
    await tester.pumpAndSettle();
    final Rect r = capsule(tester);
    // UIKit: a point at 870 puts the menu at 809.
    expect(r.top, 809);
    expect(r.left, 20);
    controller.remove();
    await tester.pumpAndSettle();
  });

  testWidgets('choosing an action calls it and the menu shrinks away', (
    WidgetTester tester,
  ) async {
    final BuildContext context = await show(tester);
    open(context, const Offset(220, 480), items(<String>['A', 'B', 'C']));
    await tester.pumpAndSettle();
    final Rect full = capsule(tester);
    await tester.tap(find.bySemanticsLabel('B'));
    await tester.pump();
    expect(chosen, <String>['B']);
    expect(find.byType(GlassEditMenu), findsNothing);
    // Its copy hides on UIKit's spring, back into the point.
    await frames(tester, 6);
    final Rect going = tester.getRect(find.byType(Glass).last);
    expect(going.width, lessThan(full.width * 0.8));
    expect(going.width, greaterThan(full.width * 0.25));
    expect(going.top, closeTo(495, 0.01));
    await tester.pumpAndSettle();
    expect(find.byType(Glass), findsNothing);
  });

  testWidgets('no frame goes by without the menu as Flutter removes it', (
    WidgetTester tester,
  ) async {
    final BuildContext context = await show(tester);
    open(context, const Offset(220, 480), items(<String>['A', 'B']));
    await tester.pumpAndSettle();
    // The glass drawn (its backdrop reads), in the frame that removes the
    // menu too: its copy shows in that very frame.
    int glassDrawn() {
      var n = 0;
      void walk(Layer? layer) {
        for (Layer? l = layer; l != null; l = l.nextSibling) {
          if (l is BackdropFilterLayer) {
            n++;
          }
          if (l is ContainerLayer) {
            walk(l.firstChild);
          }
        }
      }

      walk(tester.binding.renderViews.first.debugLayer);
      return n;
    }

    expect(glassDrawn(), greaterThan(0));
    controller.remove();
    await tester.pump();
    expect(find.byType(GlassEditMenu), findsNothing);
    expect(glassDrawn(), greaterThan(0));
    await tester.pumpAndSettle();
    expect(glassDrawn(), 0);
  });

  testWidgets('a chevron for the actions that do not fit opens them all', (
    WidgetTester tester,
  ) async {
    final BuildContext context = await show(tester);
    final List<String> labels = <String>[
      'Alpha',
      'Bravo',
      'Charlie',
      'Delta',
      'Echo',
      'Foxtrot',
    ];
    open(context, const Offset(220, 300), items(labels));
    await tester.pumpAndSettle();
    final Rect r = capsule(tester);
    expect(r.width, lessThanOrEqualTo(400));
    expect(find.bySemanticsLabel('Foxtrot'), findsNothing);
    await tester.tap(find.bySemanticsLabel('More'));
    await tester.pumpAndSettle();
    // The full menu, right edge at the capsule's, its top at the capsule's.
    final Finder last = find.text('Foxtrot');
    expect(last, findsOneWidget);
    final Rect menu = tester.getRect(
      find.ancestor(of: last, matching: find.byType(Glass)).first,
    );
    expect(menu.right, closeTo(r.right, 0.5));
    expect(menu.top, closeTo(r.top, 0.5));
    await tester.tap(find.text('Echo'));
    await tester.pumpAndSettle();
    expect(chosen, <String>['Echo']);
    expect(find.byType(GlassEditMenu), findsNothing);
    expect(find.byType(Glass), findsNothing);
  });

  testWidgets('a tap outside the full menu closes it and the edit menu', (
    WidgetTester tester,
  ) async {
    final BuildContext context = await show(tester);
    open(
      context,
      const Offset(220, 300),
      items(<String>['Alpha', 'Bravo', 'Charlie', 'Delta', 'Echo', 'Foxtrot']),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('More'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(60, 800));
    await tester.pumpAndSettle();
    expect(find.text('Foxtrot'), findsNothing);
    expect(find.byType(GlassEditMenu), findsNothing);
    expect(chosen, isEmpty);
  });

  testWidgets('a text field\'s actions, Cut, Copy and Paste first as tiles', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(440, 956);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map<Object?, Object?>)['text'] as String?;
        }
        if (call.method == 'Clipboard.hasStrings') {
          return <String, bool>{'value': true};
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final TextEditingController text = TextEditingController(
      text: 'The quick brown fox',
    );
    addTearDown(text.dispose);
    await tester.pumpWidget(
      CupertinoApp(
        home: Center(
          child: CupertinoTextField(
            controller: text,
            contextMenuBuilder: GlassEditMenu.builder,
          ),
        ),
      ),
    );
    await tester.tap(find.byType(CupertinoTextField));
    await tester.pump();
    text.selection = const TextSelection(baseOffset: 10, extentOffset: 15);
    await tester.pump();
    final EditableTextState state = tester.state<EditableTextState>(
      find.byType(EditableText),
    );
    state.showToolbar();
    await tester.pumpAndSettle();
    expect(find.byType(GlassEditMenu), findsOneWidget);
    // Below the selection, 15pt.
    final double selectionBottom = state.contextMenuAnchors.secondaryAnchor!.dy;
    expect(capsule(tester).top, closeTo(selectionBottom + 15, 0.01));
    await tester.tap(find.bySemanticsLabel('Copy'));
    await tester.pumpAndSettle();
    expect(copied, 'brown');
    expect(find.byType(GlassEditMenu), findsNothing);
  });
}
