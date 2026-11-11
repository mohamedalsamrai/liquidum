import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquidum/src/glass_backdrop.dart';

void main() {
  testWidgets('glass beside a backdrop shares its reads; glass in it, '
      'elsewhere, or over glass reads its own', (WidgetTester tester) async {
    const inside = Key('inside');
    const over1 = Key('over1');
    const over2 = Key('over2');
    const onOver1 = Key('onOver1');
    const elsewhere = Key('elsewhere');
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: Stack(
                children: <Widget>[
                  Positioned.fill(
                    child: GlassBackdrop(
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: SizedBox(key: inside, width: 50, height: 50),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 100,
                    top: 100,
                    child: SizedBox(key: over1, width: 50, height: 50),
                  ),
                  Positioned(
                    left: 200,
                    top: 100,
                    child: SizedBox(key: over2, width: 50, height: 50),
                  ),
                  Positioned(
                    left: 110,
                    top: 110,
                    child: SizedBox(key: onOver1, width: 20, height: 20),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 300,
              top: 300,
              child: SizedBox(key: elsewhere, width: 50, height: 50),
            ),
          ],
        ),
      ),
    );
    GlassShare? share(Key key) {
      final RenderBox box = tester.renderObject(find.byKey(key));
      return glassShareFor(box, box.localToGlobal(Offset.zero) & box.size);
    }

    expect(share(inside), isNull);
    final GlassShare? first = share(over1);
    expect(first, isNotNull);
    expect(share(over2), same(first));
    // Over glass that shares this frame.
    expect(share(onOver1), isNull);
    expect(share(elsewhere), isNull);
  });
}
