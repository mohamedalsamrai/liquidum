import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquidum/liquidum.dart';

// UIKit's alert (iOS 26.5, iPhone 17 Pro Max: 440 x 956, safe area 62 / 34):
// 320pt wide in the middle of the safe area; its actions are capsules 48pt
// tall, 16pt in from its sides and bottom and 8pt apart; two stand side by
// side (the cancel action on the left), more are stacked with it last.
void main() {
  Future<BuildContext> app(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1320, 2868);
    tester.view.devicePixelRatio = 3;
    tester.view.padding = const FakeViewPadding(top: 186, bottom: 102);
    addTearDown(tester.view.reset);
    late BuildContext ctx;
    await tester.pumpWidget(
      CupertinoApp(
        home: Builder(
          builder: (BuildContext context) {
            ctx = context;
            return const SizedBox.expand();
          },
        ),
      ),
    );
    return ctx;
  }

  Rect alert(WidgetTester tester) => tester.getRect(find.byType(Glass));

  Rect capsule(WidgetTester tester, String label) => tester.getRect(
    find
        .ancestor(of: find.text(label), matching: find.byType(DecoratedBox))
        .first,
  );

  testWidgets('three actions are stacked, the cancel action last', (
    WidgetTester tester,
  ) async {
    final BuildContext context = await app(tester);
    showGlassAlert(
      context: context,
      title: 'Title',
      message: 'A message',
      actions: const <GlassAlertAction>[
        GlassAlertAction(label: 'Cancel', cancel: true),
        GlassAlertAction(label: 'OK'),
        GlassAlertAction(label: 'Delete', destructive: true),
      ],
    );
    await tester.pumpAndSettle();
    final Rect a = alert(tester);
    expect(a.left, closeTo(60, 0.01));
    expect(a.width, closeTo(320, 0.01));
    // In the middle of the safe area.
    expect((a.top - 62) - (956 - 34 - a.bottom), closeTo(0, 0.01));
    final Rect ok = capsule(tester, 'OK');
    final Rect delete = capsule(tester, 'Delete');
    final Rect cancel = capsule(tester, 'Cancel');
    expect(ok.left, closeTo(76, 0.01));
    expect(ok.width, closeTo(288, 0.01));
    expect(ok.height, closeTo(48, 0.01));
    expect(delete.top - ok.bottom, closeTo(8, 0.01));
    expect(cancel.top - delete.bottom, closeTo(8, 0.01));
    expect(a.bottom - cancel.bottom, closeTo(16, 0.01));
    // The text: 30pt in, the title 22pt down, the first capsule 20.3pt
    // below the message.
    final Rect title = tester.getRect(find.text('Title'));
    final Rect message = tester.getRect(find.text('A message'));
    expect(title.left - a.left, closeTo(30, 0.01));
    expect(title.top - a.top, closeTo(22, 0.01));
    expect(message.top - title.bottom, closeTo(7.4, 0.01));
    expect(ok.top - message.bottom, closeTo(20.3, 0.01));
  });

  testWidgets('two actions stand side by side, the cancel action left', (
    WidgetTester tester,
  ) async {
    final BuildContext context = await app(tester);
    showGlassAlert(
      context: context,
      actions: const <GlassAlertAction>[
        GlassAlertAction(label: 'OK'),
        GlassAlertAction(label: 'Cancel', cancel: true),
      ],
    );
    await tester.pumpAndSettle();
    final Rect a = alert(tester);
    // No text: the actions alone, 80pt tall.
    expect(a.height, closeTo(80, 0.01));
    expect(
      capsule(tester, 'Cancel'),
      rectMoreOrLessEquals(
        Rect.fromLTWH(76, a.top + 16, 140, 48),
        epsilon: 0.01,
      ),
    );
    expect(
      capsule(tester, 'OK'),
      rectMoreOrLessEquals(
        Rect.fromLTWH(224, a.top + 16, 140, 48),
        epsilon: 0.01,
      ),
    );
  });

  testWidgets('a tap on an action closes it with that action', (
    WidgetTester tester,
  ) async {
    final BuildContext context = await app(tester);
    final List<String> pressed = <String>[];
    final List<GlassAlertAction?> results = <GlassAlertAction?>[];
    final List<GlassAlertAction> actions = <GlassAlertAction>[
      GlassAlertAction(label: 'Cancel', cancel: true, onPressed: () {}),
      GlassAlertAction(label: 'OK', onPressed: () => pressed.add('OK')),
    ];
    showGlassAlert(
      context: context,
      title: 'Title',
      actions: actions,
    ).then(results.add);
    await tester.pumpAndSettle();
    // A tap outside does nothing (UIKit's alerts wait for an action).
    await tester.tapAt(const Offset(220, 150));
    await tester.pumpAndSettle();
    expect(find.text('Title'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('Title'), findsNothing);
    expect(pressed, <String>['OK']);
    expect(results, <GlassAlertAction?>[actions[1]]);
  });

  testWidgets('a tap outside an action sheet cancels it', (
    WidgetTester tester,
  ) async {
    final BuildContext context = await app(tester);
    final List<String> pressed = <String>[];
    final List<GlassAlertAction?> results = <GlassAlertAction?>[];
    final List<GlassAlertAction> actions = <GlassAlertAction>[
      GlassAlertAction(label: 'Delete', destructive: true, onPressed: () {}),
      GlassAlertAction(
        label: 'Cancel',
        cancel: true,
        onPressed: () => pressed.add('Cancel'),
      ),
    ];
    showGlassActionSheet(
      context: context,
      title: 'Title',
      actions: actions,
    ).then(results.add);
    await tester.pumpAndSettle();
    // As UIKit's without a view to present from: the alert.
    expect(tester.getRect(find.byType(Glass)).width, closeTo(320, 0.01));
    await tester.tapAt(const Offset(220, 150));
    await tester.pumpAndSettle();
    expect(find.text('Title'), findsNothing);
    expect(pressed, <String>['Cancel']);
    expect(results, <GlassAlertAction?>[actions[1]]);
  });

  testWidgets('a text field sits between the text and the actions', (
    WidgetTester tester,
  ) async {
    final BuildContext context = await app(tester);
    final TextEditingController name = TextEditingController();
    addTearDown(name.dispose);
    final List<GlassAlertAction?> results = <GlassAlertAction?>[];
    showGlassAlert(
      context: context,
      title: 'Title',
      message: 'A message',
      textFields: <GlassAlertTextField>[
        GlassAlertTextField(controller: name, placeholder: 'Name'),
      ],
      actions: const <GlassAlertAction>[
        GlassAlertAction(label: 'Cancel', cancel: true),
        GlassAlertAction(label: 'OK'),
      ],
    ).then(results.add);
    await tester.pumpAndSettle();
    final Rect a = tester.getRect(find.byType(Glass));
    final Rect field = tester.getRect(
      find
          .ancestor(
            of: find.byType(CupertinoTextField),
            matching: find.byType(Stack),
          )
          .first,
    );
    final Rect message = tester.getRect(find.text('A message'));
    // UIKit: 290 x 48, 15pt in, 16.3pt below the message; the actions
    // 20pt below it.
    expect(field.left - a.left, closeTo(15, 0.01));
    expect(field.width, closeTo(290, 0.01));
    expect(field.height, closeTo(48, 0.01));
    expect(field.top - message.bottom, closeTo(16.3, 0.01));
    expect(
      tester.getRect(find.text('OK').first).center.dy - 24 - field.bottom,
      closeTo(20, 0.5),
    );
    // Focused: typing fills it.
    await tester.enterText(find.byType(EditableText), 'Ada');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(name.text, 'Ada');
    expect(results.single?.label, 'OK');
  });

  testWidgets('a finger slides from one action to another', (
    WidgetTester tester,
  ) async {
    final BuildContext context = await app(tester);
    final List<GlassAlertAction?> results = <GlassAlertAction?>[];
    const List<GlassAlertAction> actions = <GlassAlertAction>[
      GlassAlertAction(label: 'One'),
      GlassAlertAction(label: 'Two'),
      GlassAlertAction(label: 'Three'),
    ];
    showGlassAlert(
      context: context,
      message: 'Choose',
      actions: actions,
    ).then(results.add);
    await tester.pumpAndSettle();
    final TestGesture g = await tester.startGesture(
      tester.getCenter(find.text('One')),
    );
    await tester.pump();
    await g.moveTo(tester.getCenter(find.text('Three')));
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle();
    expect(results, <GlassAlertAction?>[actions[2]]);
  });

  testWidgets('it grows in from 1.2 times its size', (
    WidgetTester tester,
  ) async {
    final BuildContext context = await app(tester);
    showGlassAlert(context: context, title: 'Title');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pumpAndSettle();
    final Rect rest = alert(tester);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    showGlassAlert(context: context, title: 'Title');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    // UIKit, 0.05s in (critically damped, omega 22.9): 1 + 0.2 x (1 +
    // 1.145) e^-1.145 = 1.1365 times.
    await tester.pump(const Duration(milliseconds: 50));
    final double scale = alert(tester).width / rest.width;
    expect(scale, closeTo(1 + 0.2 * (1 + 1.145) * math.exp(-1.145), 0.01));
  });
}
