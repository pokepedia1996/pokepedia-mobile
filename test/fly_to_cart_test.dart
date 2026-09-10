import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/shared/widgets/fly_to_cart.dart';

/// The flight is decoration on top of a purchase that already happened, so
/// the thing to prove is that it never outlives itself and never takes the
/// page down with it when an end is missing.
final _source = GlobalKey();
final _target = GlobalKey();
const _flyer = Key('flyer');

Widget _host({bool withSource = true, bool withTarget = true}) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => Stack(
          children: [
            if (withSource)
              Positioned(
                left: 20,
                top: 400,
                child: SizedBox(key: _source, width: 100, height: 140),
              ),
            if (withTarget)
              Positioned(
                right: 10,
                top: 30,
                child: SizedBox(key: _target, width: 40, height: 40),
              ),
            Center(
              child: ElevatedButton(
                onPressed: () => flyToCart(
                  context: context,
                  from: _source,
                  to: _target,
                  child: const ColoredBox(key: _flyer, color: Colors.red),
                ),
                child: const Text('add'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('flies from the artwork and clears itself up', (tester) async {
    await tester.pumpWidget(_host());
    await tester.tap(find.text('add'));
    await tester.pump();

    // Mid-flight: on screen, and somewhere between the two ends.
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(_flyer), findsOneWidget);
    final mid = tester.getCenter(find.byKey(_flyer));
    final start = tester.getCenter(find.byKey(_source));
    final end = tester.getCenter(find.byKey(_target));
    expect(mid.dy, lessThan(start.dy));
    expect(mid.dy, greaterThan(end.dy));

    // And it leaves nothing behind.
    await tester.pumpAndSettle();
    expect(find.byKey(_flyer), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shrinks towards the cart it is landing on', (tester) async {
    await tester.pumpWidget(_host());
    await tester.tap(find.text('add'));
    await tester.pump();

    await tester.pump(const Duration(milliseconds: 60));
    final early = tester.getSize(find.byKey(_flyer));
    await tester.pump(const Duration(milliseconds: 400));
    final late_ = tester.getSize(find.byKey(_flyer));
    expect(late_.width, lessThan(early.width));

    await tester.pumpAndSettle();
  });

  testWidgets('does nothing when an end is off screen', (tester) async {
    // The buyer scrolled the artwork away, or the bar has no cart button:
    // the add still succeeded, so this must stay silent.
    await tester.pumpWidget(_host(withSource: false));
    await tester.tap(find.text('add'));
    await tester.pumpAndSettle();

    expect(find.byKey(_flyer), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('survives the page being popped mid-flight', (tester) async {
    await tester.pumpWidget(_host());
    await tester.tap(find.text('add'));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
